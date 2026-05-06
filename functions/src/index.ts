import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import vision from "@google-cloud/vision";

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
    if (!filePath || !filePath.startsWith("feedPhotos/")) return;

    // feedPhotos/{userId}/{postId}.jpg
    const parts = filePath.split("/");
    if (parts.length < 3) return;
    const filename = parts[parts.length - 1];
    const postId = filename.replace(/\.[^.]+$/, "");
    if (!postId) return;

    // Tages-Cap prüfen, bevor wir bezahlte Vision-API anfragen.
    const allowed = await tryReserveSafeSearchCall().catch(() => true);
    if (!allowed) {
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

    // 1) Eigene Posts inkl. Subcollection comments rekursiv löschen.
    const ownPosts = await db
      .collection("feed")
      .where("userId", "==", uid)
      .get();
    for (const doc of ownPosts.docs) {
      await db.recursiveDelete(doc.ref).catch((e) =>
        logger.warn("recursiveDelete post failed", { post: doc.id, error: String(e) }),
      );
    }

    // 2) Kommentare auf fremden Posts. CollectionGroup-Query, danach
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

    // 3) Eigene Reports löschen (DSGVO).
    const ownReports = await db
      .collection("reports")
      .where("reporterUid", "==", uid)
      .get();
    for (const r of ownReports.docs) {
      await r.ref.delete().catch(() => undefined);
    }

    // 4) Eigene SharedTrips inkl. participants-Subcollection.
    const ownTrips = await db
      .collection("sharedTrips")
      .where("ownerUid", "==", uid)
      .get();
    for (const t of ownTrips.docs) {
      await db.recursiveDelete(t.ref).catch((e) =>
        logger.warn("recursiveDelete trip failed", { trip: t.id, error: String(e) }),
      );
    }

    // 5) Eigene Invites.
    const ownInvites = await db
      .collection("invites")
      .where("ownerUid", "==", uid)
      .get();
    for (const i of ownInvites.docs) {
      await i.ref.delete().catch(() => undefined);
    }

    // 6) /userBlocks/{uid} und /userMeta/{uid} (samt Subcollections).
    await db.recursiveDelete(db.collection("userBlocks").doc(uid)).catch(() => undefined);
    await db.recursiveDelete(db.collection("userMeta").doc(uid)).catch(() => undefined);

    // 7) Storage: feedPhotos/{uid}/** löschen.
    try {
      const bucket = getStorage().bucket();
      await bucket.deleteFiles({ prefix: `feedPhotos/${uid}/` });
    } catch (e) {
      logger.warn("Storage cleanup failed", { uid, error: String(e) });
    }

    // 8) Auth-Account zuletzt entfernen. Damit ist der User komplett weg.
    try {
      await getAuth().deleteUser(uid);
    } catch (e) {
      logger.error("Auth deleteUser failed", { uid, error: String(e) });
      throw new HttpsError("internal", "Account-Löschung fehlgeschlagen.");
    }

    logger.info("deleteUserAccount: done", { uid });
    return { ok: true };
  },
);

// ── suggestFishSpecies: Gemini Vision Pre-Fill ──────────────────────────

// Liste exakt aus FishSpecies-Enum in lib/shared/models/catch_entry.dart.
// Reihenfolge wichtig — wir akzeptieren ausschließlich diese Werte zurück.
const SUPPORTED_SPECIES = [
  "hecht",
  "zander",
  "barsch",
  "wels",
  "forelle",
  "huchen",
  "aal",
  "andere",
  "unbekannt",
] as const;
type SuggestedSpecies = (typeof SUPPORTED_SPECIES)[number];

const GEMINI_DAILY_CAP = 5000; // Schutz gegen Kostenexplosion (~$0.14 max)
const GEMINI_REGION = "europe-west1"; // europe-west3 unterstützt gemini-2.0-flash nicht
const GEMINI_MODEL = "gemini-2.0-flash";

const GEMINI_PROMPT = `Du bist ein Bestimmungs-Assistent für deutsche Süßwasser-Raubfische.

Welche Fischart ist auf dem Bild zu sehen? Antworte AUSSCHLIESSLICH mit
genau einem dieser Werte (lowercase, ohne Anführungszeichen, ohne weiteren
Text):

- hecht       (Esox lucius)
- zander      (Sander lucioperca)
- barsch      (Perca fluviatilis, Flussbarsch)
- wels        (Silurus glanis)
- forelle     (Bach-, Regenbogen- oder Seeforelle)
- huchen      (Hucho hucho, Donaulachs)
- aal         (Anguilla anguilla)
- andere      (irgendein anderer Fisch, z.B. Karpfen, Brasse, Rotauge)
- unbekannt   (kein Fisch erkennbar oder Unsicher)

Strenge Regeln:
- Bei Unsicherheit zwischen zwei Arten → "unbekannt"
- Wenn kein Fisch zu sehen ist → "unbekannt"
- Niemals Erklärungen, niemals Zusatztext, niemals Markdown.`;

/** Holt einen kurzlebigen Access-Token vom GCP-Metadata-Server.
 *  Funktioniert zuverlässig in Cloud Run / Gen-2-Functions ohne extra Auth-Config.
 */
async function getGcpAccessToken(): Promise<string> {
  const res = await fetch(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { headers: { "Metadata-Flavor": "Google" } },
  );
  if (!res.ok) throw new Error(`Metadata token fetch failed: ${res.status}`);
  const json = await res.json() as { access_token: string };
  return json.access_token;
}

/** Ruft die Vertex AI generateContent-API per fetch auf (kein SDK). */
async function callVertexGemini(imageBase64: string): Promise<string> {
  const project = process.env.GCLOUD_PROJECT ?? "";
  const endpoint =
    `https://${GEMINI_REGION}-aiplatform.googleapis.com/v1/projects/${project}` +
    `/locations/${GEMINI_REGION}/publishers/google/models/${GEMINI_MODEL}:generateContent`;
  const token = await getGcpAccessToken();

  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      contents: [{
        role: "user",
        parts: [
          { inlineData: { mimeType: "image/jpeg", data: imageBase64 } },
          { text: GEMINI_PROMPT },
        ],
      }],
      generationConfig: { temperature: 0, maxOutputTokens: 16 },
    }),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => `HTTP ${res.status}`);
    throw new Error(`Vertex AI ${res.status}: ${errText.slice(0, 400)}`);
  }

  const data = await res.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  return data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}

async function tryReserveGeminiCall(): Promise<boolean> {
  const day = new Date().toISOString().slice(0, 10);
  const ref = db.collection("geminiUsage").doc(day);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = (snap.data()?.count as number | undefined) ?? 0;
    if (count >= GEMINI_DAILY_CAP) return false;
    tx.set(
      ref,
      { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    return true;
  });
}

/**
 * Nimmt ein kleines Thumbnail (base64 JPEG) entgegen und liefert eine
 * Gemini-basierte Fischart-Schätzung zurück. Der Client komprimiert das
 * Bild vor dem Aufruf auf ~768px / q=80 → ~80–150 KB pro Request.
 */
export const suggestFishSpecies = onCall(
  { timeoutSeconds: 30, memory: "512MiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Login erforderlich.");
    }
    const imageBase64 = request.data?.imageBase64 as string | undefined;
    if (!imageBase64 || imageBase64.length < 100) {
      throw new HttpsError("invalid-argument", "imageBase64 fehlt.");
    }
    if (imageBase64.length > 2_500_000) {
      // ~1.8 MB JPEG. Mehr brauchen wir für 768px nicht.
      throw new HttpsError("invalid-argument", "Bild zu groß.");
    }

    const allowed = await tryReserveGeminiCall().catch(() => true);
    if (!allowed) {
      logger.warn("Gemini daily cap reached", { uid: request.auth.uid });
      return { species: "unbekannt", capped: true };
    }

    try {
      const rawText = await callVertexGemini(imageBase64);
      const raw = rawText.trim().toLowerCase().replace(/[^a-zäöü]/g, "");

      const species: SuggestedSpecies = (SUPPORTED_SPECIES as readonly string[]).includes(raw)
        ? (raw as SuggestedSpecies)
        : "unbekannt";

      logger.info("Gemini species suggestion", { uid: request.auth.uid, raw, species });
      return { species, capped: false };
    } catch (e) {
      logger.error("Gemini call failed", { error: String(e) });
      // "unavailable" schickt den Message-Text zum Client durch
      // ("internal" wird von Firebase aus Sicherheitsgründen maskiert).
      throw new HttpsError("unavailable", `Bildanalyse: ${String(e)}`);
    }
  },
);

// Unterdrückt unused-Warning bei Timestamp falls oben nicht referenziert.
export type _Reserved = Timestamp;
