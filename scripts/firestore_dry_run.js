// Firestore DRY RUN Feedback Scan Script
// Scans and classifies all feedback documents without modifying data
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// CONFIRMATION FLAG - ALWAYS false for DRY RUN
const CONFIRM = false;

// Feedback identification keywords
const FEEDBACK_KEYWORDS = [
  'rating', 'score', 'scores', 'feedback', 'comment', 'הערות', 'notes',
  'instructorName', 'folder', 'exercise', 'role', 'name', 'criteriaList',
  'commandText', 'scenario', 'settlement', 'attendeesCount'
];

// Data collection
let feedbackDocuments = [];
let classificationCounts = {
  feedback_general: 0,
  feedback_defense_474: 0,
  feedback_madrichim: 0
};
let uniqueSourcePaths = new Set();
let uniqueCourseTypes = new Set();
let uniqueDepartments = new Set();

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
          path: docPath,
          id: doc.id,
          data: data,
          classification: classification
        });

        classificationCounts[classification]++;
        uniqueSourcePaths.add(path);

        // Collect unique values
        if (data.courseType) {
          uniqueCourseTypes.add(String(data.courseType));
        }
        if (data.department) {
          uniqueDepartments.add(String(data.department));
        }

        console.log(`📋 ${docPath} → ${classification}`);
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
  console.log('🔒 DRY RUN MODE – no data will be written');
  console.log('🚀 Starting Firestore feedback scan and classification');
  console.log('=' .repeat(60));

  try {
    // Get all root collections
    console.log('📂 Scanning all collections and subcollections...');
    const rootCollections = await db.listCollections();

    console.log(`Found ${rootCollections.length} root collections:`);
    rootCollections.forEach(col => console.log(`  - ${col.id}`));
    console.log('');

    // Scan each root collection recursively
    for (const collection of rootCollections) {
      await scanAllCollections(collection);
    }

  } catch (error) {
    console.error('❌ Error during scan:', error);
    process.exit(1);
  }

  // Print final summary
  console.log('\n' + '='.repeat(60));
  console.log('📊 FINAL SUMMARY');
  console.log('='.repeat(60));

  console.log(`\n📄 Total feedback documents found: ${feedbackDocuments.length}`);
  console.log(`   - feedback_general (משוב כללי): ${classificationCounts.feedback_general}`);
  console.log(`   - feedback_defense_474 (מחלקות הגנה 474): ${classificationCounts.feedback_defense_474}`);
  console.log(`   - feedback_madrichim (מיונים לקורס מדריכים): ${classificationCounts.feedback_madrichim}`);

  console.log('\n📂 Unique sourcePath values:');
  if (uniqueSourcePaths.size > 0) {
    Array.from(uniqueSourcePaths).sort().forEach(path => {
      console.log(`  - ${path}`);
    });
  } else {
    console.log('  (none found)');
  }

  console.log('\n🏷️  Unique courseType values:');
  if (uniqueCourseTypes.size > 0) {
    Array.from(uniqueCourseTypes).sort().forEach(type => {
      console.log(`  - "${type}"`);
    });
  } else {
    console.log('  (none found)');
  }

  console.log('\n🏢 Unique department values:');
  if (uniqueDepartments.size > 0) {
    Array.from(uniqueDepartments).sort().forEach(dept => {
      console.log(`  - "${dept}"`);
    });
  } else {
    console.log('  (none found)');
  }

  console.log('\n✅ DRY RUN completed successfully!');
  console.log('🔒 No data was modified during this scan.');
  console.log('Use firestore_consolidation.js with CONFIRM = true to perform actual consolidation.');

  process.exit(0);
}

// Run the scan
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});