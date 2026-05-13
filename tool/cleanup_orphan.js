#!/usr/bin/env node
/**
 * Einmaliges Admin-Cleanup-Skript für verwaiste User-Daten.
 *
 * Verwendung:
 *   cd /Users/ba34344/Private/hooked/functions
 *   node ../tool/cleanup_orphan.js --uid <USER_UID> [--dry-run]
 *
 * Voraussetzung: Application Default Credentials gesetzt, z. B.:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 * oder via `firebase login` + `gcloud auth application-default login`.
 *
 * Das Skript nutzt firebase-admin aus node_modules/ des functions-Ordners,
 * daher muss es aus dem functions-Verzeichnis heraus aufgerufen werden.
 */

"use strict";

// firebase-admin liegt in functions/node_modules/ – Pfad relativ zu diesem Skript auflösen,
// damit das Skript unabhängig vom cwd aufgerufen werden kann.
const path = require("path");
const functionsDir = path.join(__dirname, "..", "functions");
const admin = require(path.join(functionsDir, "node_modules", "firebase-admin"));

// ── CLI-Args parsen ────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const uidIdx = args.indexOf("--uid");
const dryRun = args.includes("--dry-run");

if (uidIdx === -1 || !args[uidIdx + 1]) {
  console.error("Fehler: --uid <USER_UID> ist erforderlich.");
  console.error("Beispiel: node ../tool/cleanup_orphan.js --uid abc123xyz");
  process.exit(1);
}

const TARGET_UID = args[uidIdx + 1];

if (dryRun) {
  console.log("[DRY-RUN] Es werden keine Daten gelöscht.");
}
console.log(`Starte Cleanup für UID: ${TARGET_UID}`);

// ── Firebase initialisieren ────────────────────────────────────────────────
admin.initializeApp({
  projectId: "hooked-fangtagebuch",
  storageBucket: "hooked-fangtagebuch.firebasestorage.app",
});
const db = admin.firestore();
const { FieldValue } = admin.firestore;
const bucket = admin.storage().bucket();

// ── Helper ─────────────────────────────────────────────────────────────────
async function safeDelete(ref, label) {
  if (dryRun) {
    console.log(`  [DRY-RUN] würde löschen: ${label}`);
    return;
  }
  try {
    await ref.delete();
    console.log(`  ✓ gelöscht: ${label}`);
  } catch (e) {
    console.warn(`  ⚠ Fehler beim Löschen (${label}): ${e.message}`);
  }
}

async function safeRecursiveDelete(ref, label) {
  if (dryRun) {
    console.log(`  [DRY-RUN] würde rekursiv löschen: ${label}`);
    return;
  }
  try {
    await db.recursiveDelete(ref);
    console.log(`  ✓ rekursiv gelöscht: ${label}`);
  } catch (e) {
    console.warn(`  ⚠ Fehler beim rekursiven Löschen (${label}): ${e.message}`);
  }
}

// ── Hauptlogik ─────────────────────────────────────────────────────────────
async function run() {
  const uid = TARGET_UID;

  // 1) Sicherheitscheck: Auth-User sollte bereits gelöscht sein.
  //    Falls nicht, abbrechen und darauf hinweisen.
  try {
    await admin.auth().getUser(uid);
    console.error(
      `\nAbbruch: Auth-User ${uid} existiert noch. Bitte zuerst den Account\n` +
        `in der Firebase Console oder via deleteUserAccount-Function löschen.\n`
    );
    process.exit(1);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      console.log("✓ Auth-User ist bereits gelöscht — fahre mit Cleanup fort.\n");
    } else {
      console.error(`Auth-Prüfung fehlgeschlagen: ${e.message}`);
      process.exit(1);
    }
  }

  // 2) feed-Posts (inkl. comments-Subcollection)
  console.log("→ Feed-Posts…");
  const feedSnap = await db.collection("feed").where("userId", "==", uid).get();
  console.log(`  ${feedSnap.size} Posts gefunden`);
  for (const doc of feedSnap.docs) {
    await safeRecursiveDelete(doc.ref, `feed/${doc.id}`);
  }

  // 3) Kommentare auf fremden Posts
  console.log("→ Kommentare auf fremden Posts…");
  const commentsSnap = await db.collectionGroup("comments").where("userId", "==", uid).get();
  console.log(`  ${commentsSnap.size} Kommentare gefunden`);
  const decrementByPost = new Map();
  for (const c of commentsSnap.docs) {
    const postRef = c.ref.parent.parent;
    if (postRef) {
      decrementByPost.set(postRef.path, (decrementByPost.get(postRef.path) ?? 0) + 1);
    }
    await safeDelete(c.ref, c.ref.path);
  }
  for (const [path, n] of decrementByPost) {
    if (dryRun) {
      console.log(`  [DRY-RUN] commentCount auf ${path} um ${n} dekrementieren`);
      continue;
    }
    await db.doc(path).update({ commentCount: FieldValue.increment(-n) }).catch((e) => {
      console.warn(`  ⚠ commentCount-Update fehlgeschlagen (${path}): ${e.message}`);
    });
    console.log(`  ✓ commentCount auf ${path} um ${n} dekrementiert`);
  }

  // 4) Reports
  console.log("→ Reports…");
  const reportsSnap = await db.collection("reports").where("reporterUid", "==", uid).get();
  console.log(`  ${reportsSnap.size} Reports gefunden`);
  for (const r of reportsSnap.docs) await safeDelete(r.ref, r.ref.path);

  // 5) SharedTrips
  console.log("→ SharedTrips…");
  const tripsSnap = await db.collection("sharedTrips").where("ownerUid", "==", uid).get();
  console.log(`  ${tripsSnap.size} SharedTrips gefunden`);
  for (const t of tripsSnap.docs) await safeRecursiveDelete(t.ref, t.ref.path);

  // 6) Invites
  console.log("→ Invites…");
  const invitesSnap = await db.collection("invites").where("ownerUid", "==", uid).get();
  console.log(`  ${invitesSnap.size} Invites gefunden`);
  for (const i of invitesSnap.docs) await safeDelete(i.ref, i.ref.path);

  // 7) userBlocks + userMeta
  console.log("→ userBlocks + userMeta…");
  await safeRecursiveDelete(db.collection("userBlocks").doc(uid), `userBlocks/${uid}`);
  await safeRecursiveDelete(db.collection("userMeta").doc(uid), `userMeta/${uid}`);

  // 8) Handle freigeben + userProfile löschen
  console.log("→ userProfile + Handle…");
  const profileSnap = await db.collection("userProfiles").doc(uid).get();
  if (profileSnap.exists) {
    const handle = profileSnap.data()?.handle;
    if (handle) {
      await safeDelete(db.collection("handles").doc(handle), `handles/${handle}`);
    } else {
      console.log("  kein Handle gefunden");
    }
    await safeRecursiveDelete(db.collection("userProfiles").doc(uid), `userProfiles/${uid}`);
  } else {
    console.log("  userProfile existiert nicht (bereits gelöscht)");
  }

  // 9) Storage
  console.log("→ Storage…");
  for (const prefix of [`feedPhotos/${uid}/`, `profilePhotos/${uid}`]) {
    if (dryRun) {
      const [files] = await bucket.getFiles({ prefix });
      console.log(`  [DRY-RUN] ${files.length} Dateien unter ${prefix}`);
      continue;
    }
    try {
      const [files] = await bucket.getFiles({ prefix });
      await bucket.deleteFiles({ prefix });
      console.log(`  ✓ ${files.length} Dateien gelöscht: ${prefix}`);
    } catch (e) {
      console.warn(`  ⚠ Storage-Fehler (${prefix}): ${e.message}`);
    }
  }

  console.log(`\n✓ Cleanup für UID ${uid} abgeschlossen.`);
}

run().catch((e) => {
  console.error("Unerwarteter Fehler:", e);
  process.exit(1);
});
