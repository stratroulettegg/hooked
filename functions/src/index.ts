import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";

initializeApp();

const DATABASE_ID = "default";
const db = getFirestore(DATABASE_ID);

// ── Konfiguration ──────────────────────────────────────────────────────────
// Anzahl unterschiedlicher Reporter, ab der ein Inhalt automatisch
// versteckt wird.
const AUTO_HIDE_THRESHOLD = 3;

// Sliding-Window-Limits pro User pro Stunde.
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1h
const POSTS_PER_HOUR = 5;
const COMMENTS_PER_HOUR = 30;
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
      tx.set(ref, { [key]: arr }, { merge: true });
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

// ── onPostCreated: Rate-Limit ─────────────────────────────────────────────

export const onPostCreated = onDocumentCreated(
  { document: "feed/{postId}", database: DATABASE_ID },
  async (event) => {
    const data = event.data?.data();
    const userId = data?.userId as string | undefined;
    if (!userId) return;
    if (await isOverLimit(userId, "posts", POSTS_PER_HOUR)) {
      logger.warn("Post rate-limit hit – deleting", { userId, postId: event.params.postId });
      await event.data?.ref.delete().catch(() => undefined);
    }
  },
);

// ── onCommentCreated: Rate-Limit ──────────────────────────────────────────

export const onCommentCreated = onDocumentCreated(
  { document: "feed/{postId}/comments/{commentId}", database: DATABASE_ID },
  async (event) => {
    const data = event.data?.data();
    const userId = data?.userId as string | undefined;
    if (!userId) return;
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

// Unterdrückt unused-Warning bei Timestamp falls oben nicht referenziert.
export type _Reserved = Timestamp;
