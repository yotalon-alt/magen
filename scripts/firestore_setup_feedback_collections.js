// Firestore Setup Feedback Collections Script
// Creates the basic structure for feedback collections with example documents
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Collections to create
const FEEDBACK_COLLECTIONS = [
  'feedback_general',
  'feedback_defense_474',
  'feedback_madrichim'
];

// Example document structure
const EXAMPLE_DOC = {
  rating: 5,
  comment: 'דוגמה למסמך משוב - ניתן למחוק לאחר בדיקה',
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  source: 'setup_script',
  metadata: {
    version: '1.0',
    type: 'example',
    description: 'מסמך דוגמה שנוצר על ידי סקריפט ההתקנה'
  }
};

// Function to check if example document exists
async function checkExampleExists(collectionName) {
  try {
    const docRef = db.collection(collectionName).collection('items').doc('example');
    const doc = await docRef.get();
    return doc.exists;
  } catch (error) {
    console.log(`⚠️  Error checking ${collectionName}:`, error.message);
    return false;
  }
}

// Function to create example document
async function createExampleDocument(collectionName) {
  try {
    const docRef = db.collection(collectionName).collection('items').doc('example');
    await docRef.set(EXAMPLE_DOC);
    console.log(`✅ Created example document in ${collectionName}/items/example`);
    return true;
  } catch (error) {
    console.error(`❌ Error creating example in ${collectionName}:`, error.message);
    return false;
  }
}

async function main() {
  console.log('🚀 Starting Firestore feedback collections setup');
  console.log('This script creates the basic structure with example documents');
  console.log('=' .repeat(60));

  let createdCount = 0;
  let existingCount = 0;

  try {
    for (const collectionName of FEEDBACK_COLLECTIONS) {
      console.log(`\n🔍 Checking collection: ${collectionName}`);

      const exists = await checkExampleExists(collectionName);

      if (exists) {
        console.log(`📁 Collection ${collectionName} already has example document`);
        existingCount++;
      } else {
        console.log(`📝 Creating example document for ${collectionName}...`);
        const success = await createExampleDocument(collectionName);
        if (success) {
          createdCount++;
        }
      }
    }

  } catch (error) {
    console.error('❌ Error during setup:', error);
    process.exit(1);
  }

  // Print final summary
  console.log('\n' + '='.repeat(60));
  console.log('📊 SETUP SUMMARY');
  console.log('='.repeat(60));

  console.log(`\n✅ Setup completed successfully!`);
  console.log(`   - Collections checked: ${FEEDBACK_COLLECTIONS.length}`);
  console.log(`   - New example documents created: ${createdCount}`);
  console.log(`   - Existing collections found: ${existingCount}`);

  console.log('\n🏗️  Created structure:');
  FEEDBACK_COLLECTIONS.forEach(name => {
    console.log(`   - ${name}/items/example`);
  });

  console.log('\n📋 Example document structure:');
  console.log('   - rating: number (1-5)');
  console.log('   - comment: string');
  console.log('   - createdAt: serverTimestamp');
  console.log('   - source: string');
  console.log('   - metadata: map with version, type, description');

  console.log('\n🔒 No existing data was modified or deleted.');
  console.log('The example documents can be deleted after testing the new Flutter pages.');

  process.exit(0);
}

// Run the setup
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});