// Batch-create or upsert instructor users via Firebase Admin SDK.
// Prereqs: place serviceAccount.json one level above this file (project root).
const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const auth = admin.auth();
const db = admin.firestore();

const users = [
  { name: 'חן', email: 'chen@test.com', password: '123456', role: 'instructor' },
  { name: 'יוגב', email: 'yogev@test.com', password: '123456', role: 'instructor' },
  { name: 'לירון', email: 'liron@test.com', password: '123456', role: 'instructor' },
  { name: 'דוד', email: 'david@test.com', password: '123456', role: 'instructor' },
];

let createdCount = 0;
let existingCount = 0;

async function upsertUser(u) {
  let userRecord;
  let created = false;
  try {
    userRecord = await auth.getUserByEmail(u.email);
    existingCount += 1;
    console.log(`Exists: ${u.email} -> ${userRecord.uid}`);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      userRecord = await auth.createUser({
        email: u.email,
        password: u.password,
        displayName: u.name,
        emailVerified: true,
        disabled: false,
      });
      created = true;
      createdCount += 1;
      console.log(`Created: ${u.email} -> ${userRecord.uid}`);
    } else {
      throw err;
    }
  }

  const docRef = db.collection('users').doc(userRecord.uid);
  const data = {
    email: u.email,
    name: u.name,
    role: u.role,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (created) {
    data.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await docRef.set(data, { merge: true });
  console.log(`Firestore set: users/${userRecord.uid} role=${u.role}`);
}

async function main() {
  for (const u of users) {
    await upsertUser(u);
  }
  console.log(`Summary: created=${createdCount}, existed=${existingCount}`);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
