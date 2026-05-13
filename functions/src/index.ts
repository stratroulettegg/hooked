import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import { auth as authV1 } from "firebase-functions/v1";
import { onDocumentWritten, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import { getMessaging } from "firebase-admin/messaging";
import vision from "@google-cloud/vision";
import { findBannedWord } from "./community_words";

initializeApp();

// Alle Functions in europe-west3 — Co-Location mit Firestore + Storage
// und DSGVO-freundlich (Verarbeitung in der EU).
setGlobalOptions({ region: "europe-west3" });

const DATABASE_ID = "default";
const db = getFirestore(DATABASE_ID);

// ── Konfiguration ──────────────────────────────────────────────────────────
// Anzahl unterschiedlicher Reporter, ab der ein Inhalt automatisch
// versteckt wird.
const AUTO_HIDE_THRESHOLD = 5;

// Anzahl unterschiedlicher Reporter, ab der ein User automatisch
// shadowBanned wird (Posts werden für Andere ausgeblendet).
const USER_SHADOWBAN_THRESHOLD = 3;

// Sliding-Window-Limits pro User pro Stunde.
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1h
const POSTS_PER_HOUR = 20;
const COMMENTS_PER_HOUR = 60;
const REPORTS_PER_HOUR = 20;

// ── Helpers ────────────────────────────────────────────────────────────────

/**
 * Sliding-Window-Rate-Limit auf /userMeta/{uid}.{key}. Speichert Timestamps
 * der jüngsten Aktionen (in ms). Liefert true, wenn das Limit überschritten
 * wurde.
 */
async function isOverLimit(
  uid: string,
  key: "posts" | "comments" | "reports",
  limit: number,
): Promise<boolean> {
  const ref = db.collection("userMeta").doc(uid);
  const now = Date.now();
  const cutoff = now - RATE_LIMIT_WINDOW_MS;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const arr = ((snap.data()?.[key] as number[] | undefined) ?? []).filter(
      (ts) => ts > cutoff,
    );
    if (arr.length >= limit) {
      tx.set(
        ref,
        {
          [key]: arr,
          lastBlockedKind: key,
          lastBlockedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return true;
    }
    arr.push(now);
    tx.set(ref, { [key]: arr, updatedAt: FieldValue.serverTimestamp() }, {
      merge: true,
    });
    return false;
  });
}

function aggregateKey(
  targetType: string,
  postId?: string,
  commentId?: string,
  targetUid?: string,
): string | null {
  if (targetType === "post" && postId) return `post_${postId}`;
  if (targetType === "comment" && postId && commentId) {
    return `comment_${postId}_${commentId}`;
  }
  if (targetType === "user" && targetUid) return `user_${targetUid}`;
  return null;
}

// ── onReportCreated: Aggregat + Auto-Hide ─────────────────────────────────

export const onReportCreated = onDocumentCreated(
  { document: "reports/{reportId}", database: DATABASE_ID },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const targetType = data.targetType as string | undefined;
    const reporterUid = data.reporterUid as string | undefined;
    const postId = data.postId as string | undefined;
    const commentId = data.commentId as string | undefined;
    const targetUid = data.targetUid as string | undefined;

    if (!targetType || !reporterUid) return;

    // Rate-Limit: wer in der letzten Stunde zu viele Reports abgesetzt hat,
    // dessen Report wird wieder gelöscht.
    if (await isOverLimit(reporterUid, "reports", REPORTS_PER_HOUR)) {
      logger.warn("Report rate-limit hit", { reporterUid });
      await event.data?.ref.delete().catch(() => undefined);
      return;
    }

    const key = aggregateKey(targetType, postId, commentId, targetUid);
    if (!key) {
      logger.warn("Report ohne valide Target-ID", { targetType, postId, commentId, targetUid });
      return;
    }

    const aggRef = db.collection("reportAggregates").doc(key);
    const reporters = await db.runTransaction(async (tx) => {
      const snap = await tx.get(aggRef);
      const existing =
        ((snap.data()?.reporterUids as string[] | undefined) ?? []);
      if (existing.includes(reporterUid)) {
        return existing;
      }
      const next = [...existing, reporterUid];
      tx.set(
        aggRef,
        {
          targetType,
          postId: postId ?? null,
          commentId: commentId ?? null,
          targetUid: targetUid ?? null,
          reporterUids: next,
          count: next.length,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return next;
    });

    if (reporters.length < AUTO_HIDE_THRESHOLD) return;

    // Schwelle erreicht → Inhalt verstecken/löschen.
    if (targetType === "post" && postId) {
      await db
        .collection("feed")
        .doc(postId)
        .set(
          {
            hidden: true,
            hiddenReason: "auto_reports",
            hiddenAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
        .catch((e) => logger.error("Auto-hide post failed", e));
      logger.info("Post auto-hidden", { postId, reporters: reporters.length });
    } else if (targetType === "comment" && postId && commentId) {
      await db
        .collection("feed")
        .doc(postId)
        .collection("comments")
        .doc(commentId)
        .delete()
        .catch((e) => logger.error("Auto-delete comment failed", e));
      logger.info("Comment auto-deleted", {
        postId,
        commentId,
        reporters: reporters.length,
      });
    } else if (targetType === "user" && targetUid) {
      // User-Reports: ab USER_SHADOWBAN_THRESHOLD Reportern shadow-bannen.
      // Manuelle Account-Sperre bleibt zusätzlich möglich (admin-only).
      if (reporters.length >= USER_SHADOWBAN_THRESHOLD) {
        await db
          .collection("userProfiles")
          .doc(targetUid)
          .set(
            {
              shadowBanned: true,
              shadowBannedReason: "auto_reports",
              shadowBannedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          )
          .catch((e) => logger.error("Auto shadow-ban failed", e));
        // Bestehende Posts dieses Users im Feed verstecken.
        const userPosts = await db
          .collection("feed")
          .where("userId", "==", targetUid)
          .get()
          .catch(() => null);
        if (userPosts) {
          await Promise.all(
            userPosts.docs.map((d) =>
              d.ref
                .set(
                  {
                    hidden: true,
                    hiddenReason: "author_shadowbanned",
                    hiddenAt: FieldValue.serverTimestamp(),
                  },
                  { merge: true },
                )
                .catch(() => undefined),
            ),
          );
        }
        logger.warn("User auto shadow-banned", {
          targetUid,
          reporters: reporters.length,
        });
      }
    }
  },
);

// ── onUserProfileWritten: Wortfilter für DisplayName / Steckbrief ───────
//
// Clients schreiben displayName/steckbrief direkt in Firestore (siehe
// firestore.rules). Dieser Trigger prüft den Inhalt und scrubbt verbotene
// Felder rückwirkend. Bei wiederholten Verstößen wird zusätzlich
// shadowBanned gesetzt.
export const onUserProfileWritten = onDocumentWritten(
  { document: "userProfiles/{uid}", database: DATABASE_ID },
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;
    const uid = event.params.uid;

    const displayName = (after.displayName as string | undefined) ?? "";
    const steckbrief = (after.steckbrief as string | undefined) ?? "";

    const dnHit = displayName ? findBannedWord(displayName) : null;
    const sbHit = steckbrief ? findBannedWord(steckbrief) : null;
    if (!dnHit && !sbHit) return;

    const update: Record<string, unknown> = {
      moderationFlaggedAt: FieldValue.serverTimestamp(),
      shadowBanned: true,
      shadowBannedReason: "banned_words",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (dnHit) {
      update.displayName = "Angler:in";
      update.moderationFlaggedDisplayName = displayName;
    }
    if (sbHit) {
      update.steckbrief = null;
      update.moderationFlaggedSteckbrief = steckbrief;
    }
    await event.data?.after.ref.set(update, { merge: true }).catch((e) =>
      logger.error("Profile scrub failed", { uid, error: String(e) }),
    );
    // Counter erhöhen (für Mods sichtbar).
    await db
      .collection("moderationCounters")
      .doc(uid)
      .set(
        {
          uid,
          bannedWordHits: FieldValue.increment(1),
          lastHitAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      )
      .catch(() => undefined);
    logger.warn("Profile scrubbed for banned words", { uid, dnHit, sbHit });
  },
);

// ── onPostCreated: Identity-Override + Rate-Limit ───────────────────────

async function overwriteIdentity(
  ref: FirebaseFirestore.DocumentReference,
  userId: string,
  current: { userName?: unknown; userPhotoUrl?: unknown },
): Promise<void> {
  // Server-seitig die Anzeigedaten aus Firebase Auth durchsetzen, damit
  // niemand fremde Namen/Avatare in den Feed schmuggeln kann.
  try {
    const user = await getAuth().getUser(userId);
    const trusted = {
      userName: user.displayName ?? null,
      userPhotoUrl: user.photoURL ?? null,
    };
    if (
      trusted.userName === (current.userName ?? null) &&
      trusted.userPhotoUrl === (current.userPhotoUrl ?? null)
    ) {
      return;
    }
    await ref.set(trusted, { merge: true });
  } catch (e) {
    logger.warn("Identity overwrite failed", { userId, error: String(e) });
  }
}

export const onPostCreated = onDocumentCreated(
  { document: "feed/{postId}", database: DATABASE_ID },
  async (event) => {
    const data = event.data?.data();
    const userId = data?.userId as string | undefined;
    if (!userId) return;

    if (event.data) {
      await overwriteIdentity(event.data.ref, userId, {
        userName: data?.userName,
        userPhotoUrl: data?.userPhotoUrl,
      });
    }

    // Author shadowBanned? Post sofort verstecken.
    try {
      const profileSnap = await db.collection("userProfiles").doc(userId).get();
      if (profileSnap.data()?.shadowBanned === true) {
        await event.data?.ref.set(
          {
            hidden: true,
            hiddenReason: "author_shadowbanned",
            hiddenAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        logger.info("Post auto-hidden (author shadowbanned)", {
          userId,
          postId: event.params.postId,
        });
      }
    } catch (e) {
      logger.warn("shadowBan check failed", { userId, error: String(e) });
    }

    // Wortfilter für Post-Text (Caption).
    const postText = (data?.text as string | undefined) ?? "";
    const postHit = postText ? findBannedWord(postText) : null;
    if (postHit) {
      logger.warn("Post blocked by word filter", {
        userId,
        postId: event.params.postId,
        hit: postHit,
      });
      await event.data?.ref.set(
        {
          hidden: true,
          hiddenReason: "banned_words",
          hiddenAt: FieldValue.serverTimestamp(),
          text: "",
        },
        { merge: true },
      );
      await db
        .collection("moderationCounters")
        .doc(userId)
        .set(
          {
            uid: userId,
            bannedWordHits: FieldValue.increment(1),
            lastHitAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
        .catch(() => undefined);
    }

    if (await isOverLimit(userId, "posts", POSTS_PER_HOUR)) {
      logger.warn("Post rate-limit hit – deleting", { userId, postId: event.params.postId });
      await event.data?.ref.delete().catch(() => undefined);
    }
  },
);

// ── onCommentCreated: Identity-Override + Rate-Limit ────────────────────

export const onCommentCreated = onDocumentCreated(
  { document: "feed/{postId}/comments/{commentId}", database: DATABASE_ID },
  async (event) => {
    const data = event.data?.data();
    const userId = data?.userId as string | undefined;
    if (!userId) return;

    if (event.data) {
      await overwriteIdentity(event.data.ref, userId, {
        userName: data?.userName,
        userPhotoUrl: data?.userPhotoUrl,
      });
    }

    // Wortfilter: Kommentar mit verbotenen Begriffen sofort löschen.
    const text = (data?.text as string | undefined) ?? "";
    const bannedHit = text ? findBannedWord(text) : null;
    if (bannedHit) {
      logger.warn("Comment blocked by word filter", {
        userId,
        postId: event.params.postId,
        commentId: event.params.commentId,
        hit: bannedHit,
      });
      await event.data?.ref.delete().catch(() => undefined);
      await db
        .collection("feed")
        .doc(event.params.postId)
        .update({ commentCount: FieldValue.increment(-1) })
        .catch(() => undefined);
      await db
        .collection("moderationCounters")
        .doc(userId)
        .set(
          {
            uid: userId,
            bannedWordHits: FieldValue.increment(1),
            lastHitAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
        .catch(() => undefined);
      return;
    }

    if (await isOverLimit(userId, "comments", COMMENTS_PER_HOUR)) {
      logger.warn("Comment rate-limit hit – deleting", {
        userId,
        postId: event.params.postId,
        commentId: event.params.commentId,
      });
      await event.data?.ref.delete().catch(() => undefined);
      // commentCount-Increment vom Client zurücknehmen.
      await db
        .collection("feed")
        .doc(event.params.postId)
        .update({ commentCount: FieldValue.increment(-1) })
        .catch(() => undefined);
    }
  },
);

// ── onPhotoUploaded: SafeSearch ─────────────────────────────────────────

// SafeSearch-Likelihood-Levels: VERY_UNLIKELY < UNLIKELY < POSSIBLE < LIKELY
// < VERY_LIKELY. Wir sind beim "violence"-Score absichtlich tolerant
// (blutende Fische triggern "violence" häufig false-positiv) und blocken
// nur bei adult oder racy mit hoher Konfidenz.
const LIKELIHOOD_RANK: Record<string, number> = {
  UNKNOWN: 0,
  VERY_UNLIKELY: 1,
  UNLIKELY: 2,
  POSSIBLE: 3,
  LIKELY: 4,
  VERY_LIKELY: 5,
};

function shouldBlock(annotation: {
  adult?: string | null;
  racy?: string | null;
  medical?: string | null;
}): { block: boolean; reason: string } {
  const adult = LIKELIHOOD_RANK[annotation.adult ?? "UNKNOWN"] ?? 0;
  const racy = LIKELIHOOD_RANK[annotation.racy ?? "UNKNOWN"] ?? 0;
  const medical = LIKELIHOOD_RANK[annotation.medical ?? "UNKNOWN"] ?? 0;
  if (adult >= 4) return { block: true, reason: "adult" };
  if (racy >= 5) return { block: true, reason: "racy" };
  if (medical >= 5) return { block: true, reason: "medical" };
  return { block: false, reason: "" };
}

const visionClient = new vision.ImageAnnotatorClient();

// Hard-Cap gegen Kostenexplosion: pro Tag werden nur so viele Bilder gegen
// SafeSearch geprüft. Darüber hinaus werden Posts vorsorglich versteckt
// (sicher > sparsam), Datei aber nicht gelöscht. Cloud Vision SafeSearch
// kostet ~$1.50 / 1000 calls (erste 1000/Monat gratis).
const SAFESEARCH_DAILY_CAP = 2000;

async function tryReserveSafeSearchCall(): Promise<boolean> {
  const day = new Date().toISOString().slice(0, 10); // YYYY-MM-DD UTC
  const ref = db.collection("visionUsage").doc(day);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = (snap.data()?.count as number | undefined) ?? 0;
    if (count >= SAFESEARCH_DAILY_CAP) return false;
    tx.set(
      ref,
      { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return true;
  });
}

export const onPhotoUploaded = onObjectFinalized(
  {},
  async (event) => {
    const filePath = event.data.name;
    if (!filePath) return;

    const isFeedPhoto = filePath.startsWith("feedPhotos/");
    const isProfilePhoto = filePath.startsWith("profilePhotos/");
    if (!isFeedPhoto && !isProfilePhoto) return;

    // feedPhotos/{userId}/{postId}.jpg  oder  profilePhotos/{userId}.jpg
    const parts = filePath.split("/");
    let postId: string | null = null;
    let profileUid: string | null = null;
    if (isFeedPhoto) {
      if (parts.length < 3) return;
      const filename = parts[parts.length - 1];
      postId = filename.replace(/\.[^.]+$/, "");
      if (!postId) return;
    } else {
      // profilePhotos/{uid}.{ext}
      const filename = parts[parts.length - 1];
      profileUid = filename.replace(/\.[^.]+$/, "");
      if (!profileUid) return;
    }

    // Tages-Cap prüfen, bevor wir bezahlte Vision-API anfragen.
    const allowed = await tryReserveSafeSearchCall().catch(() => true);
    if (!allowed) {
      if (isFeedPhoto && postId) {
        logger.warn("SafeSearch daily cap reached – hiding post defensively", { postId });
        await db
          .collection("feed")
          .doc(postId)
          .set(
            {
              hidden: true,
              hiddenReason: "safesearch_capped",
              hiddenAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          )
          .catch((e) => logger.error("Hide (capped) failed", e));
      } else if (isProfilePhoto && profileUid) {
        logger.warn("SafeSearch daily cap reached – flagging profile defensively", { profileUid });
        await db
          .collection("userProfiles")
          .doc(profileUid)
          .set(
            {
              shadowBanned: true,
              shadowBannedReason: "safesearch_capped",
              shadowBannedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          )
          .catch(() => undefined);
      }
      return;
    }

    let safeSearch;
    try {
      const [result] = await visionClient.safeSearchDetection(
        `gs://${event.data.bucket}/${filePath}`,
      );
      safeSearch = result.safeSearchAnnotation;
    } catch (e) {
      logger.error("SafeSearch failed", { filePath, error: String(e) });
      return;
    }
    if (!safeSearch) return;

    const { block, reason } = shouldBlock({
      adult: safeSearch.adult as string | null | undefined,
      racy: safeSearch.racy as string | null | undefined,
      medical: safeSearch.medical as string | null | undefined,
    });
    logger.info("SafeSearch result", {
      filePath,
      adult: safeSearch.adult,
      racy: safeSearch.racy,
      medical: safeSearch.medical,
      violence: safeSearch.violence,
      block,
    });
    if (!block) return;

    if (isFeedPhoto && postId) {
      await db
        .collection("feed")
        .doc(postId)
        .set(
          {
            hidden: true,
            hiddenReason: `safesearch_${reason}`,
            hiddenAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
        .catch((e) => logger.error("Hide post failed", e));
    } else if (isProfilePhoto && profileUid) {
      // Profilbild aus dem Profil entfernen + Account markieren.
      await db
        .collection("userProfiles")
        .doc(profileUid)
        .set(
          {
            photoUrl: null,
            shadowBanned: true,
            shadowBannedReason: `safesearch_${reason}`,
            shadowBannedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
        .catch((e) => logger.error("Clear profile photo failed", e));
      // Auth-Profil ebenfalls bereinigen.
      await getAuth()
        .updateUser(profileUid, { photoURL: null as unknown as string })
        .catch(() => undefined);
      logger.warn("Profile photo blocked by SafeSearch", { profileUid, reason });
    }

    await getStorage()
      .bucket(event.data.bucket)
      .file(filePath)
      .delete({ ignoreNotFound: true })
      .catch((e) => logger.error("Delete photo failed", e));

    logger.warn("Photo hidden by SafeSearch", { filePath, reason });
  },
);

// ── deleteUserAccount: DSGVO-Cascade ────────────────────────────────────

/**
 * Löscht alle Cloud-Daten des aufrufenden Users und anschließend den
 * Auth-Account. Wird vom Client per httpsCallable aufgerufen, BEVOR der
 * Client `signOut` ausführt. Nach erfolgreichem Return ist der Account
 * vollständig entfernt (DSGVO Art. 17, App-Store-Guideline 5.1.1(v)).
 *
 * Bewusst keine Atomarität über alle Collections — fällt der Lauf in der
 * Mitte aus, kann der User die Funktion erneut aufrufen (idempotent).
 */
export const deleteUserAccount = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Login erforderlich.");
    }
    logger.info("deleteUserAccount: start", { uid });

    // 1) Auth-Account ZUERST löschen — damit werden sofort alle aktiven
    //    Sessions (inkl. anderer Geräte) ungültig. Neue Firestore-Writes
    //    mit diesem UID können danach keine frischen Tokens mehr erhalten
    //    und schlagen an den Security Rules fehl. Das verhindert die
    //    Race-Condition bei Mehrgeräte-Logins (Device B hatte pending
    //    offline-Writes, die nach dem Query-basierten Cleanup noch
    //    durchgekommen sind).
    try {
      await getAuth().deleteUser(uid);
    } catch (e: unknown) {
      // Falls der Auth-User bereits gelöscht ist (z. B. zweiter Aufruf),
      // einfach fortfahren — der Cleanup soll trotzdem laufen.
      const code = (e as { code?: string }).code ?? "";
      if (code !== "auth/user-not-found") {
        logger.error("Auth deleteUser failed", { uid, error: String(e) });
        throw new HttpsError("internal", "Account-Löschung fehlgeschlagen.");
      }
      logger.info("deleteUserAccount: auth user already gone, continuing cleanup", { uid });
    }

    // 2) Eigene Posts inkl. Subcollection comments rekursiv löschen.
    const ownPosts = await db
      .collection("feed")
      .where("userId", "==", uid)
      .get();
    for (const doc of ownPosts.docs) {
      await db.recursiveDelete(doc.ref).catch((e) =>
        logger.warn("recursiveDelete post failed", { post: doc.id, error: String(e) }),
      );
    }

    // 3) Kommentare auf fremden Posts. CollectionGroup-Query, danach
    //    commentCount auf den Parent-Posts dekrementieren.
    const ownComments = await db
      .collectionGroup("comments")
      .where("userId", "==", uid)
      .get();
    const decrementByPost = new Map<string, number>();
    for (const c of ownComments.docs) {
      const postRef = c.ref.parent.parent;
      if (postRef) {
        decrementByPost.set(postRef.path, (decrementByPost.get(postRef.path) ?? 0) + 1);
      }
      await c.ref.delete().catch(() => undefined);
    }
    for (const [path, n] of decrementByPost) {
      await db
        .doc(path)
        .update({ commentCount: FieldValue.increment(-n) })
        .catch(() => undefined);
    }

    // 4) Eigene Reports löschen (DSGVO).
    const ownReports = await db
      .collection("reports")
      .where("reporterUid", "==", uid)
      .get();
    for (const r of ownReports.docs) {
      await r.ref.delete().catch(() => undefined);
    }

    // 5) Eigene SharedTrips inkl. participants-Subcollection.
    const ownTrips = await db
      .collection("sharedTrips")
      .where("ownerUid", "==", uid)
      .get();
    for (const t of ownTrips.docs) {
      await db.recursiveDelete(t.ref).catch((e) =>
        logger.warn("recursiveDelete trip failed", { trip: t.id, error: String(e) }),
      );
    }

    // 6) Eigene Invites.
    const ownInvites = await db
      .collection("invites")
      .where("ownerUid", "==", uid)
      .get();
    for (const i of ownInvites.docs) {
      await i.ref.delete().catch(() => undefined);
    }

    // 7) /userBlocks/{uid} und /userMeta/{uid} (samt Subcollections).
    await db.recursiveDelete(db.collection("userBlocks").doc(uid)).catch(() => undefined);
    await db.recursiveDelete(db.collection("userMeta").doc(uid)).catch(() => undefined);

    // 8) /userProfiles/{uid} + reservierten Handle freigeben.
    try {
      const profileSnap = await db.collection("userProfiles").doc(uid).get();
      const handle = profileSnap.data()?.handle as string | undefined;
      if (handle) {
        await db.collection("handles").doc(handle).delete().catch(() => undefined);
      }
      await db.recursiveDelete(db.collection("userProfiles").doc(uid)).catch(() => undefined);
    } catch (e) {
      logger.warn("UserProfile cleanup failed", { uid, error: String(e) });
    }

    // 9) Storage: feedPhotos/{uid}/** + profilePhotos/{uid}.* löschen.
    try {
      const bucket = getStorage().bucket();
      await bucket.deleteFiles({ prefix: `feedPhotos/${uid}/` });
      // Profilbild liegt als `profilePhotos/{uid}.jpg` (oder ggf. .png)
      // direkt im Prefix — `deleteFiles` mit Prefix matcht alle Endungen.
      await bucket.deleteFiles({ prefix: `profilePhotos/${uid}` });
    } catch (e) {
      logger.warn("Storage cleanup failed", { uid, error: String(e) });
    }

    logger.info("deleteUserAccount: done", { uid });
    return { ok: true };
  },
);

// ── cleanupDeletedUser: Safety-Net via Auth-Trigger ──────────────────────
//
// Feuert immer dann, wenn ein Auth-User gelöscht wird — unabhängig davon,
// ob es über deleteUserAccount, die Firebase-Console oder direkt per
// Admin-SDK passiert. Stellt sicher, dass keine Waisen-Daten übrigbleiben,
// selbst wenn deleteUserAccount mit einem Fehler abgebrochen ist oder
// offline-gecachte Writes von einem zweiten Gerät kurz vor der Löschung
// noch durchgekommen sind.
export const cleanupDeletedUser = authV1.user().onDelete(async (user) => {
  const uid = user.uid;
  logger.info("cleanupDeletedUser: start", { uid });

  // Feed-Posts (inkl. comments Subcollection).
  const ownPosts = await db
    .collection("feed")
    .where("userId", "==", uid)
    .get();
  for (const doc of ownPosts.docs) {
    await db.recursiveDelete(doc.ref).catch((e) =>
      logger.warn("cleanupDeletedUser: recursiveDelete post failed", { post: doc.id, error: String(e) }),
    );
  }

  // Kommentare auf fremden Posts.
  const ownComments = await db
    .collectionGroup("comments")
    .where("userId", "==", uid)
    .get();
  const decrementByPost = new Map<string, number>();
  for (const c of ownComments.docs) {
    const postRef = c.ref.parent.parent;
    if (postRef) {
      decrementByPost.set(postRef.path, (decrementByPost.get(postRef.path) ?? 0) + 1);
    }
    await c.ref.delete().catch(() => undefined);
  }
  for (const [path, n] of decrementByPost) {
    await db
      .doc(path)
      .update({ commentCount: FieldValue.increment(-n) })
      .catch(() => undefined);
  }

  // Reports, SharedTrips, Invites, userBlocks, userMeta.
  const ownReports = await db.collection("reports").where("reporterUid", "==", uid).get();
  for (const r of ownReports.docs) await r.ref.delete().catch(() => undefined);

  const ownTrips = await db.collection("sharedTrips").where("ownerUid", "==", uid).get();
  for (const t of ownTrips.docs) {
    await db.recursiveDelete(t.ref).catch(() => undefined);
  }

  const ownInvites = await db.collection("invites").where("ownerUid", "==", uid).get();
  for (const i of ownInvites.docs) await i.ref.delete().catch(() => undefined);

  await db.recursiveDelete(db.collection("userBlocks").doc(uid)).catch(() => undefined);
  await db.recursiveDelete(db.collection("userMeta").doc(uid)).catch(() => undefined);

  // Handle freigeben + userProfile löschen.
  try {
    const profileSnap = await db.collection("userProfiles").doc(uid).get();
    const handle = profileSnap.data()?.handle as string | undefined;
    if (handle) {
      await db.collection("handles").doc(handle).delete().catch(() => undefined);
    }
    await db.recursiveDelete(db.collection("userProfiles").doc(uid)).catch(() => undefined);
  } catch (e) {
    logger.warn("cleanupDeletedUser: UserProfile cleanup failed", { uid, error: String(e) });
  }

  // Storage-Dateien.
  try {
    const bucket = getStorage().bucket();
    await bucket.deleteFiles({ prefix: `feedPhotos/${uid}/` });
    await bucket.deleteFiles({ prefix: `profilePhotos/${uid}` });
  } catch (e) {
    logger.warn("cleanupDeletedUser: Storage cleanup failed", { uid, error: String(e) });
  }

  logger.info("cleanupDeletedUser: done", { uid });
});

// Unterdrückt unused-Warning bei Timestamp falls oben nicht referenziert.
export type _Reserved = Timestamp;

// ── claimHandle: Atomare Username-Reservierung ──────────────────────────

const HANDLE_RE = /^[a-z0-9._]+$/;
const HANDLE_RESERVED = new Set<string>([
  "admin", "administrator", "hooked", "support", "system", "null",
  "me", "self", "root", "official", "moderator", "mod", "team",
  "help", "staff", "fischer", "angler",
]);
const HANDLE_CHANGE_COOLDOWN_MS = 30 * 24 * 60 * 60 * 1000; // 30 Tage

function validateHandle(raw: unknown): string {
  if (typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "Benutzername fehlt.");
  }
  const h = raw.trim().toLowerCase();
  if (h.length < 3) {
    throw new HttpsError("invalid-argument", "Mindestens 3 Zeichen.");
  }
  if (h.length > 24) {
    throw new HttpsError("invalid-argument", "Höchstens 24 Zeichen.");
  }
  if (!HANDLE_RE.test(h)) {
    throw new HttpsError(
      "invalid-argument",
      "Nur Kleinbuchstaben, Zahlen, Punkt und Unterstrich erlaubt.",
    );
  }
  if (h.startsWith(".") || h.startsWith("_") || h.endsWith(".") || h.endsWith("_")) {
    throw new HttpsError(
      "invalid-argument",
      "Darf nicht mit . oder _ beginnen oder enden.",
    );
  }
  if (h.includes("..") || h.includes("__")) {
    throw new HttpsError("invalid-argument", "Keine doppelten . oder _.");
  }
  if (HANDLE_RESERVED.has(h)) {
    throw new HttpsError("invalid-argument", "Dieser Benutzername ist reserviert.");
  }
  if (findBannedWord(h)) {
    throw new HttpsError(
      "invalid-argument",
      "Dieser Benutzername verstößt gegen unsere Community-Regeln.",
    );
  }
  return h;
}

/**
 * Reserviert ein Handle für den aufrufenden User. Atomare Transaktion:
 * - Prüft Format
 * - Prüft Cooldown (30 Tage seit letzter Änderung)
 * - Prüft `handles/{newHandle}` ist frei (oder gehört bereits dem User)
 * - Gibt alten Handle des Users frei, falls vorhanden
 * - Schreibt `handles/{newHandle} = {uid, claimedAt}`
 * - Setzt `userProfiles/{uid}.handle + handleChangedAt`
 */
export const claimHandle = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Login erforderlich.");
  }
  const handle = validateHandle((request.data ?? {}).handle);

  const profileRef = db.collection("userProfiles").doc(uid);
  const newHandleRef = db.collection("handles").doc(handle);

  await db.runTransaction(async (tx) => {
    const [profileSnap, newHandleSnap] = await Promise.all([
      tx.get(profileRef),
      tx.get(newHandleRef),
    ]);

    const profileData = profileSnap.data() ?? {};
    const oldHandle = profileData.handle as string | undefined;

    // No-Op, wenn der User exakt diesen Handle schon hat.
    if (oldHandle === handle) {
      return;
    }

    // Cooldown nur bei tatsächlicher Änderung (nicht beim ersten Claim).
    if (oldHandle) {
      const last = profileData.handleChangedAt as
        | FirebaseFirestore.Timestamp
        | undefined;
      if (last) {
        const diff = Date.now() - last.toMillis();
        if (diff < HANDLE_CHANGE_COOLDOWN_MS) {
          const days = Math.ceil(
            (HANDLE_CHANGE_COOLDOWN_MS - diff) / (24 * 60 * 60 * 1000),
          );
          throw new HttpsError(
            "failed-precondition",
            `Du kannst deinen Benutzernamen erst in ${days} Tag(en) wieder ändern.`,
          );
        }
      }
    }

    // Belegung prüfen.
    if (newHandleSnap.exists) {
      const ownerUid = newHandleSnap.data()?.uid as string | undefined;
      if (ownerUid && ownerUid !== uid) {
        throw new HttpsError(
          "already-exists",
          "Dieser Benutzername ist bereits vergeben.",
        );
      }
    }

    // Alten Handle freigeben.
    if (oldHandle && oldHandle !== handle) {
      tx.delete(db.collection("handles").doc(oldHandle));
    }

    // Neuen Handle reservieren.
    tx.set(newHandleRef, {
      uid,
      claimedAt: FieldValue.serverTimestamp(),
    });

    // Profil-Doc aktualisieren (legt es ggf. an).
    tx.set(
      profileRef,
      {
        handle,
        handleChangedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        ...(profileSnap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    );
  });

  logger.info("Handle claimed", { uid, handle });
  return { ok: true, handle };
});

// ── Notifications: Inbox + FCM ─────────────────────────────────────────────

type NotifType = "like" | "comment" | "follow" | "reply";

const PUSH_COALESCE_MS = 5 * 60 * 1000; // 5 Min

interface InboxItemBase {
  type: NotifType;
  postId?: string | null;
  commentId?: string | null;
  parentCommentId?: string | null;
  actors: string[]; // uid-Liste, neueste zuerst
  actorNames: { [uid: string]: string };
  actorPhotos: { [uid: string]: string };
  count: number;
  updatedAt: FirebaseFirestore.FieldValue;
  createdAt?: FirebaseFirestore.FieldValue;
  readAt?: null;
  lastPushAt?: number; // ms — fürs Coalescing
}

function inboxKey(
  type: NotifType,
  postId?: string,
  actorUid?: string,
  parentCommentId?: string,
): string {
  if (type === "follow" && actorUid) return `follow_${actorUid}`;
  if (type === "reply" && postId && parentCommentId) {
    return `reply_${postId}_${parentCommentId}`;
  }
  if ((type === "like" || type === "comment") && postId) {
    return `${type}_${postId}`;
  }
  return `${type}_unknown`;
}

async function pushFcm(
  recipientUid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  // Quiet-Hours / globale Pref: Wir respektieren nur das harte Server-Flag
  // `pushDisabled` im userProfile. Quiet-Hours bleiben Client-seitig
  // (lokale Notifications werden eh stumm geschaltet).
  const profileSnap = await db.collection("userProfiles").doc(recipientUid).get();
  const profile = profileSnap.data() ?? {};
  if (profile.pushDisabled === true) return;

  const tokensSnap = await db
    .collection("userProfiles")
    .doc(recipientUid)
    .collection("fcmTokens")
    .get();
  if (tokensSnap.empty) return;

  const tokens = tokensSnap.docs.map((d) => d.id);
  const messaging = getMessaging();

  // sendEachForMulticast: einzelne Failures pro Token bekommen wir zurück
  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    apns: {
      payload: {
        aps: {
          sound: "default",
          // iOS-Threading: gleicher thread-id → Apple gruppiert in der
          // Banner-Liste auf dem Lockscreen.
          "thread-id": data.threadId ?? data.type,
        },
      },
    },
    android: {
      priority: "high",
      notification: {
        channelId: "social",
        // Android-Threading: gleicher tag → System ersetzt vorherige
        // Notification statt zu stapeln (gewollt bei Coalescing).
        tag: data.threadId ?? data.type,
      },
    },
  });

  // Tote Tokens aufräumen.
  const dead: string[] = [];
  res.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error?.code ?? "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      dead.push(tokens[i]);
    } else if (r.error) {
      logger.warn("FCM send error", { uid: recipientUid, code, msg: r.error.message });
    }
  });
  if (dead.length > 0) {
    const batch = db.batch();
    for (const t of dead) {
      batch.delete(
        db.collection("userProfiles").doc(recipientUid).collection("fcmTokens").doc(t),
      );
    }
    await batch.commit().catch(() => undefined);
  }
}

interface ActorInfo {
  uid: string;
  name: string;
  photo: string;
}

async function loadActor(uid: string): Promise<ActorInfo> {
  const snap = await db.collection("userProfiles").doc(uid).get();
  const d = snap.data() ?? {};
  return {
    uid,
    name: (d.displayName as string | undefined)?.trim() || "Angler:in",
    photo: (d.photoUrl as string | undefined) ?? "",
  };
}

/**
 * Schreibt/aktualisiert ein Inbox-Item für `recipientUid` und sendet
 * — soweit zulässig — eine Push-Notification. Das Coalescing-Fenster
 * verhindert, dass wir bei Like-Spam alle paar Sekunden pushen.
 */
async function upsertInbox(
  recipientUid: string,
  type: NotifType,
  actorUid: string,
  options: {
    postId?: string;
    commentId?: string;
    commentText?: string;
    parentCommentId?: string;
  } = {},
): Promise<void> {
  if (recipientUid === actorUid) return; // niemals an sich selbst

  // Block-Liste prüfen: Wenn der Empfänger den Actor blockiert hat,
  // gar keine Notification anlegen.
  const blockSnap = await db.collection("userBlocks").doc(recipientUid).get();
  const blocked = (blockSnap.data()?.blocked as string[] | undefined) ?? [];
  if (blocked.includes(actorUid)) return;

  const key = inboxKey(type, options.postId, actorUid, options.parentCommentId);
  const ref = db
    .collection("userProfiles")
    .doc(recipientUid)
    .collection("inbox")
    .doc(key);

  const actor = await loadActor(actorUid);
  const now = Date.now();

  const shouldPush = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as
      | (Partial<InboxItemBase> & { lastPushAt?: number })
      | undefined;

    let actors = data?.actors ?? [];
    actors = [actorUid, ...actors.filter((u) => u !== actorUid)].slice(0, 50);
    const actorNames = { ...(data?.actorNames ?? {}), [actorUid]: actor.name };
    const actorPhotos = { ...(data?.actorPhotos ?? {}), [actorUid]: actor.photo };

    const lastPushAt = data?.lastPushAt ?? 0;
    const push = now - lastPushAt > PUSH_COALESCE_MS;

    tx.set(
      ref,
      {
        type,
        postId: options.postId ?? null,
        commentId: options.commentId ?? null,
        parentCommentId: options.parentCommentId ?? null,
        commentText: options.commentText ?? null,
        actors,
        actorNames,
        actorPhotos,
        count: actors.length,
        readAt: null,
        updatedAt: FieldValue.serverTimestamp(),
        ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
        ...(push ? { lastPushAt: now } : {}),
      },
      { merge: true },
    );

    return push;
  });

  if (!shouldPush) return;

  // Push zusammenbauen.
  let title = "";
  let body = "";
  const data: Record<string, string> = {
    type,
    threadId: key,
    postId: options.postId ?? "",
    commentId: options.commentId ?? "",
    actorUid,
  };

  if (type === "like") {
    title = "Neuer Like";
    body = `${actor.name} hat deinen Fang geliked.`;
  } else if (type === "comment") {
    title = "Neuer Kommentar";
    const txt = (options.commentText ?? "").trim();
    body = txt.length > 0
      ? `${actor.name}: ${txt.length > 80 ? txt.slice(0, 77) + "…" : txt}`
      : `${actor.name} hat deinen Fang kommentiert.`;
  } else if (type === "follow") {
    title = "Neuer Follower";
    body = `${actor.name} folgt dir jetzt.`;
  } else if (type === "reply") {
    title = "Neue Antwort";
    const txt = (options.commentText ?? "").trim();
    body = txt.length > 0
      ? `${actor.name}: ${txt.length > 80 ? txt.slice(0, 77) + "…" : txt}`
      : `${actor.name} hat auf deinen Kommentar geantwortet.`;
  }

  await pushFcm(recipientUid, title, body, data).catch((e) =>
    logger.error("pushFcm failed", { recipientUid, key, err: e }),
  );
}

// ── onLikeChanged: feed/{postId} update auf likedBy ─────────────────────────

export const onLikeChanged = onDocumentUpdated(
  { document: "feed/{postId}", database: DATABASE_ID },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeLikes = ((before.likedBy as string[] | undefined) ?? []);
    const afterLikes = ((after.likedBy as string[] | undefined) ?? []);
    const added = afterLikes.filter((u) => !beforeLikes.includes(u));
    if (added.length === 0) return;

    const ownerUid = after.userId as string | undefined;
    const postId = event.params.postId as string;
    if (!ownerUid) return;

    // Bei Mehrfach-Likes in derselben Update-Ladung: jeden Actor einzeln
    // einsortieren — Coalescing kümmert sich um Push-Reduktion.
    for (const actorUid of added) {
      await upsertInbox(ownerUid, "like", actorUid, { postId }).catch((e) =>
        logger.error("upsertInbox(like) failed", { postId, actorUid, err: e }),
      );
    }
  },
);

// ── onFollowCreated: userProfiles/{uid}/followers/{followerUid} ─────────────

export const onFollowCreated = onDocumentCreated(
  {
    document: "userProfiles/{uid}/followers/{followerUid}",
    database: DATABASE_ID,
  },
  async (event) => {
    const recipientUid = event.params.uid as string;
    const actorUid = event.params.followerUid as string;
    await upsertInbox(recipientUid, "follow", actorUid).catch((e) =>
      logger.error("upsertInbox(follow) failed", { recipientUid, actorUid, err: e }),
    );
  },
);

// ── onCommentNotification: feed/{postId}/comments/{commentId} ───────────────

export const onCommentNotification = onDocumentCreated(
  {
    document: "feed/{postId}/comments/{commentId}",
    database: DATABASE_ID,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const actorUid = data.userId as string | undefined;
    const text = (data.text as string | undefined) ?? "";
    const parentId = data.parentId as string | undefined;
    const postId = event.params.postId as string;
    const commentId = event.params.commentId as string;
    if (!actorUid) return;

    // Post-Owner ermitteln.
    const postSnap = await db.collection("feed").doc(postId).get();
    const ownerUid = postSnap.data()?.userId as string | undefined;

    // Reply-Pfad: Wenn parentId gesetzt ist, Parent-Autor benachrichtigen.
    let parentAuthorUid: string | undefined;
    if (parentId) {
      const parentSnap = await db
        .collection("feed")
        .doc(postId)
        .collection("comments")
        .doc(parentId)
        .get();
      parentAuthorUid = parentSnap.data()?.userId as string | undefined;
      if (
        parentAuthorUid &&
        parentAuthorUid !== actorUid
      ) {
        await upsertInbox(parentAuthorUid, "reply", actorUid, {
          postId,
          commentId,
          parentCommentId: parentId,
          commentText: text,
        }).catch((e) =>
          logger.error("upsertInbox(reply) failed", {
            postId,
            parentId,
            actorUid,
            err: e,
          }),
        );
      }
    }

    // Post-Owner benachrichtigen — aber nicht doppelt, falls Parent-Autor
    // bereits der Post-Autor ist (dann reicht die Reply-Benachrichtigung).
    if (
      ownerUid &&
      ownerUid !== actorUid &&
      ownerUid !== parentAuthorUid
    ) {
      await upsertInbox(ownerUid, "comment", actorUid, {
        postId,
        commentId,
        commentText: text,
      }).catch((e) =>
        logger.error("upsertInbox(comment) failed", { postId, actorUid, err: e }),
      );
    }
  },
);

// ── RevenueCat-Webhook ───────────────────────────────────────────────────
// Empfängt Subscription-Events aus RevenueCat (siehe docs/MONETIZATION.md).
// Setzt Custom-Auth-Claim `pro: true|false` und spiegelt den aktuellen
// Pro-Status in `users/{uid}/billing/subscription`.
//
// **Setup**:
//   1. Webhook-URL im RC-Dashboard hinterlegen:
//      https://europe-west3-hooked-fangtagebuch.cloudfunctions.net/revenuecatWebhook
//   2. Authorization-Header mit gemeinsamem Secret konfigurieren:
//      `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET`
//   3. Den gleichen Secret-Wert im RC-Dashboard als
//      "Authorization Header" eintragen (Format: `Bearer <secret>`).
//
// **Sicherheit**: Strikt prüfen — ohne gültigen Header → 401.

const REVENUECAT_WEBHOOK_SECRET = defineSecret("REVENUECAT_WEBHOOK_SECRET");

/** Entitlement, dem `pro: true` entspricht (siehe Bootstrap.entitlementId). */
const PRO_ENTITLEMENT_ID = "hooked_pro";

/** RC-Event-Typen, die Pro aktivieren / verlängern. */
const PRO_GRANT_EVENTS = new Set<string>([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
]);

/** RC-Event-Typen, die Pro entziehen. */
const PRO_REVOKE_EVENTS = new Set<string>([
  "EXPIRATION",
  "CANCELLATION", // hier nur loggen — bis Ablauf bleibt Pro aktiv
  "BILLING_ISSUE",
  "SUBSCRIPTION_PAUSED",
]);

/** Webhook ist immutable & idempotent: gleiche Events können mehrfach ankommen. */
export const revenuecatWebhook = onRequest(
  { secrets: [REVENUECAT_WEBHOOK_SECRET], cors: false },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const expected = REVENUECAT_WEBHOOK_SECRET.value();
    const auth = req.header("Authorization") ?? "";
    if (!expected || auth !== `Bearer ${expected}`) {
      logger.warn("revenuecatWebhook: bad auth", { auth: auth.slice(0, 12) });
      res.status(401).send("Unauthorized");
      return;
    }

    // Body-Schema: https://www.revenuecat.com/docs/webhooks
    const event = (req.body?.event ?? {}) as Record<string, unknown>;
    const type = String(event.type ?? "");
    const appUserId = String(event.app_user_id ?? "");
    const productId = String(event.product_id ?? "");
    const expirationMs = Number(event.expiration_at_ms ?? 0);
    const eventId = String(event.id ?? `${type}_${appUserId}_${Date.now()}`);

    if (!appUserId || appUserId.startsWith("$RCAnonymousID")) {
      // Anonyme RC-User: noch nicht mit Firebase verknüpft — wir können
      // keinen Custom-Claim setzen. Trotzdem 200, damit RC nicht retried.
      logger.info("revenuecatWebhook: anonymous user, skipping", { type, appUserId });
      res.status(200).send("ok-skip-anon");
      return;
    }

    const grants = PRO_GRANT_EVENTS.has(type);
    const revokes = PRO_REVOKE_EVENTS.has(type);

    try {
      // 1. Subscription-Doc spiegeln (audit trail).
      await db
        .collection("users").doc(appUserId)
        .collection("billing").doc("subscription")
        .set(
          {
            lastEventType: type,
            lastEventId: eventId,
            productId: productId || null,
            proExpiresAt: expirationMs > 0 ? Timestamp.fromMillis(expirationMs) : null,
            updatedAt: FieldValue.serverTimestamp(),
            entitlementId: PRO_ENTITLEMENT_ID,
            isPro: grants,
          },
          { merge: true },
        );

      // 2. Custom-Auth-Claim. Pro = true bei Grant; bei Revoke nur wenn
      //    bereits abgelaufen (CANCELLATION soll bis Ablauf gelten).
      const nowMs = Date.now();
      const stillEntitled =
        grants || (expirationMs > 0 && expirationMs > nowMs);

      try {
        const userRecord = await getAuth().getUser(appUserId);
        const existing = (userRecord.customClaims ?? {}) as Record<string, unknown>;
        await getAuth().setCustomUserClaims(appUserId, {
          ...existing,
          pro: stillEntitled === true,
          proExpiresAt: expirationMs > 0 ? expirationMs : null,
        });
      } catch (e) {
        // User existiert ggf. nicht (RC kennt UID, Firebase-Auth aber nicht
        // mehr — z.B. nach Account-Löschung). Loggen, kein Retry-Trigger.
        logger.warn("revenuecatWebhook: setCustomUserClaims failed", {
          appUserId,
          err: String(e),
        });
      }

      logger.info("revenuecatWebhook: processed", {
        type, appUserId, productId, grants, revokes, stillEntitled,
      });
      res.status(200).send("ok");
    } catch (e) {
      logger.error("revenuecatWebhook: failed", { type, appUserId, err: String(e) });
      res.status(500).send("internal");
    }
  },
);
