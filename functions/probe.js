const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'hooked-fangtagebuch' });
const db = admin.firestore();
db.settings({ databaseId: 'default' });
(async () => {
  const uid = 'YxLBZvyOiISWARQ5bqfZ8h5WDBB3';
  for (const c of ['catches','spots','waterbodies','trips','water_days','meta']) {
    const snap = await db.collection('users').doc(uid).collection(c).limit(5).get();
    console.log(`${c}: ${snap.size} docs`);
    snap.forEach(d => console.log(`  - ${d.id}`));
  }
})().catch(e => { console.error(e); process.exit(1); });
