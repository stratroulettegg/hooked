import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { logger } from "firebase-functions/v2";
import vision from "@google-cloud/vision";

initializeApp();

const DATABASE_ID = "default";
const db = getFirestore(DATABASE_ID);

// ── Konfiguration ──────────────────────────────────────────────────────────
// Anzahl unterschiedlicher Reporter, ab der ein Inhalt automatisch
// versteckt wird.
const AUTO_HIDE_THRESHOLD = 5;

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
      // Nutzer-Reports sammeln wir nur — Account-Sperren passieren manuell.
      logger.warn("User report threshold reached", {
        targetUid,
        reporters: reporters.length,
      });
    }
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

export const onPhotoUploaded = onObjectFinalized(
  { region: "europe-west3" },
  async (event) => {
    const filePath = event.data.name;
    if (!filePath || !filePath.startsWith("feedPhotos/")) return;

    // feedPhotos/{userId}/{postId}.jpg
    const parts = filePath.split("/");
    if (parts.length < 3) return;
    const filename = parts[parts.length - 1];
    const postId = filename.replace(/\.[^.]+$/, "");
    if (!postId) return;

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
      postId,
      adult: safeSearch.adult,
      racy: safeSearch.racy,
      medical: safeSearch.medical,
      violence: safeSearch.violence,
      block,
    });
    if (!block) return;

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

    await getStorage()
      .bucket(event.data.bucket)
      .file(filePath)
      .delete({ ignoreNotFound: true })
      .catch((e) => logger.error("Delete photo failed", e));

    logger.warn("Post hidden by SafeSearch", { postId, reason });
  },
);

// Unterdrückt unused-Warning bei Timestamp falls oben nicht referenziert.
export type _Reserved = Timestamp;
