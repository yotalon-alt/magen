// Firestore Migration Script
// Migrates feedback documents to organized collections
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// CONFIRMATION FLAG - SET TO true ONLY AFTER CAREFUL REVIEW
const CONFIRM = false; // ⚠️  CHANGE TO true ONLY AFTER DRY RUN AND MANUAL APPROVAL

if (!CONFIRM) {
  console.log('🔒 DRY RUN MODE – No data will be written');
  console.log('Set CONFIRM = true to perform actual migration');
  console.log('=' .repeat(60));
}

// Feedback identification keywords
const FEEDBACK_KEYWORDS = [
  'rating', 'score', 'scores', 'feedback', 'comment', 'הערות', 'notes',
  'instructorName', 'folder', 'exercise', 'role', 'name', 'criteriaList',
  'commandText', 'scenario', 'settlement', 'attendeesCount'
];

// Data collection
let feedbackDocuments = [];
let migrationCounts = {
  feedback_general: 0,
  feedback_defense_474: 0,
  feedback_madrichim: 0
};
let uniqueSourcePaths = new Set();

// Classification function
function classifyFeedback(data) {
  const folder = String(data.folder || '').toLowerCase();
  const exercise = String(data.exercise || '').toLowerCase();
  const courseType = String(data.courseType || '').toLowerCase();

  // Instructor course selections
  if (folder.includes('מיונים לקורס מדריכים') ||
      courseType.includes('מדריך') ||
      courseType.includes('מדריכים') ||
      courseType.includes('קורס מדריכים')) {
    return 'feedback_madrichim';
  }

  // Defense department 474 exercises
  if (folder.includes('מטווחי ירי') ||
      exercise.includes('מעגל פתוח') ||
      exercise.includes('מעגל פרוץ') ||
      exercise.includes('סריקות רחוב') ||
      courseType.includes('הגנה')) {
    return 'feedback_defense_474';
  }

  // General feedback
  return 'feedback_general';
}

// Function to check if a document looks like a feedback document
function isFeedbackDocument(data) {
  let keywordCount = 0;
  for (const keyword of FEEDBACK_KEYWORDS) {
    if (data.hasOwnProperty(keyword)) {
      keywordCount++;
    }
  }
  return keywordCount >= 2; // At least 2 feedback-related fields
}

// Function to migrate document to target collection
async function migrateDocument(docInfo) {
  const { ref, path, id, data, classification } = docInfo;

  // Prepare migrated data
  const migratedData = {
    ...data,
    sourcePath: path, // Save original path
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Add createdAt if missing
  if (!migratedData.createdAt) {
    migratedData.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  // Get target collection
  const targetCollection = db.collection(classification);

  if (CONFIRM) {
    // Perform actual migration with merge
    await targetCollection.doc(id).set(migratedData, { merge: true });
    console.log(`✅ MIGRATED: ${path} → ${classification}/${id}`);
  } else {
    // Dry run - show what would happen
    console.log(`🔄 Would migrate: ${path} → ${classification}/${id}`);
  }

  migrationCounts[classification]++;
}

// Recursive function to scan all collections and subcollections
async function scanAllCollections(collectionRef, currentPath = '') {
  const path = currentPath ? `${currentPath}/${collectionRef.id}` : collectionRef.id;

  try {
    const snapshot = await collectionRef.get();

    // Process each document
    for (const doc of snapshot.docs) {
      const docPath = `${path}/${doc.id}`;
      const data = doc.data();

      // Check if this is a feedback document
      if (isFeedbackDocument(data)) {
        const classification = classifyFeedback(data);

        feedbackDocuments.push({
          ref: doc.ref,
          path: docPath,
          id: doc.id,
          data: data,
          classification: classification
        });

        uniqueSourcePaths.add(path);
      }

      // Recursively scan subcollections
      const subcollections = await doc.listCollections();
      for (const subcollection of subcollections) {
        await scanAllCollections(subcollection, docPath);
      }
    }
  } catch (error) {
    console.error(`❌ Error scanning ${path}:`, error.message);
  }
}

async function main() {
  console.log('🚀 Starting Firestore feedback migration');
  if (CONFIRM) {
    console.log('⚠️  MIGRATION MODE ENABLED - Data will be copied to new collections');
  } else {
    console.log('🔒 DRY RUN MODE - No data will be modified');
  }
  console.log('=' .repeat(60));

  try {
    // Step 1: Scan all collections for feedback documents
    console.log('🔍 Scanning for feedback documents...');
    const rootCollections = await db.listCollections();

    for (const collection of rootCollections) {
      await scanAllCollections(collection);
    }

    console.log(`\n📄 Found ${feedbackDocuments.length} feedback documents to migrate`);

    // Step 2: Migrate each document
    console.log('\n🔄 Migrating documents...');
    for (const docInfo of feedbackDocuments) {
      await migrateDocument(docInfo);
    }

  } catch (error) {
    console.error('❌ Error during migration:', error);
    process.exit(1);
  }

  // Step 3: Print final report
  console.log('\n' + '='.repeat(60));
  console.log('📊 MIGRATION REPORT');
  console.log('='.repeat(60));

  console.log(`\n📋 Documents processed: ${feedbackDocuments.length}`);
  console.log(`   - Migrated to feedback_general: ${migrationCounts.feedback_general}`);
  console.log(`   - Migrated to feedback_defense_474: ${migrationCounts.feedback_defense_474}`);
  console.log(`   - Migrated to feedback_madrichim: ${migrationCounts.feedback_madrichim}`);

  console.log('\n📂 Source paths:');
  Array.from(uniqueSourcePaths).sort().forEach(path => {
    console.log(`  - ${path}`);
  });

  if (CONFIRM) {
    console.log('\n✅ Migration completed successfully!');
    console.log('All feedback documents have been copied to organized collections.');
    console.log('Original documents remain unchanged.');
  } else {
    console.log('\n🔒 Dry run completed.');
    console.log('Review the output above and set CONFIRM = true to perform actual migration.');
  }

  process.exit(0);
}

// Run the migration
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});