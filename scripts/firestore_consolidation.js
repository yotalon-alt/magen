// Firestore Feedback Consolidation Script
// Merges and fixes all feedback documents into organized structure
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// CONFIRMATION FLAG - SET TO true TO ENABLE WRITES
const CONFIRM = false; // ⚠️  SET TO true ONLY AFTER CAREFUL REVIEW AND DRY RUN

if (!CONFIRM) {
  console.log('🔒 DRY RUN – אין כתיבה למסד הנתונים');
  console.log('הסקריפט יראה מה יעשה אבל לא ישנה נתונים.');
  console.log('כדי לבצע כתיבה אמיתית, שנה CONFIRM = true;');
  console.log('=' .repeat(60));
}

// Data collection
let feedbackDocuments = [];
let classificationStats = {
  madrichim: 0,
  defense474: 0,
  general: 0
};
let sourcePaths = new Set();
let normalizationChanges = [];

// Feedback identification keywords (Hebrew and English)
const FEEDBACK_KEYWORDS = [
  'rating', 'score', 'scores', 'feedback', 'comment', 'הערות', 'notes',
  'instructorName', 'folder', 'exercise', 'role', 'name', 'criteriaList',
  'commandText', 'scenario', 'settlement', 'attendeesCount'
];

// Classification functions
function classifyFeedback(data) {
  const courseType = String(data.courseType || '').toLowerCase();
  const department = String(data.department || '');

  // Instructor course
  if (courseType.includes('מדריך') ||
      courseType.includes('מדריכים') ||
      courseType.includes('קורס מדריכים')) {
    return 'madrichim';
  }

  // Defense department 474
  if (courseType.includes('הגנה') || department === '474') {
    return 'defense474';
  }

  // General feedback
  return 'general';
}

// Normalization functions
function normalizeCourseType(value, classification) {
  if (!value) {
    switch (classification) {
      case 'madrichim': return 'מדריכים';
      case 'defense474': return 'מחלקות הגנה';
      default: return 'כללי';
    }
  }

  const str = String(value).toLowerCase();
  if (str.includes('מדריך') || str.includes('קורס מדריכים')) {
    if (value !== 'מדריכים') {
      normalizationChanges.push(`courseType: "${value}" → "מדריכים"`);
    }
    return 'מדריכים';
  }

  return value;
}

function normalizeDepartment(value) {
  if (!value) return null;

  const str = String(value).trim();
  const normalizedValues = ['הגנה474', 'הגנה 474', '474'];

  if (normalizedValues.includes(str)) {
    if (str !== '474') {
      normalizationChanges.push(`department: "${str}" → "474"`);
    }
    return '474';
  }

  return str;
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
          ref: doc.ref,
          path: docPath,
          id: doc.id,
          data: data,
          classification: classification
        });

        classificationStats[classification]++;
        sourcePaths.add(path);

        if (!CONFIRM) {
          console.log(`📋 Would classify: ${docPath} → ${classification}`);
        }
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

// Function to get target collection reference
function getTargetCollection(classification) {
  switch (classification) {
    case 'madrichim':
      return db.collection('feedbacks').doc('madrichim').collection('items');
    case 'defense474':
      return db.collection('feedbacks').doc('defense').collection('474').collection('items');
    case 'general':
      return db.collection('feedbacks').doc('general').collection('items');
    default:
      return db.collection('feedbacks').doc('general').collection('items');
  }
}

// Function to normalize and copy document
async function copyToTarget(docInfo) {
  const { ref, path, id, data, classification } = docInfo;

  // Normalize the data
  const normalizedData = {
    ...data,
    courseType: normalizeCourseType(data.courseType, classification),
    department: normalizeDepartment(data.department),
    createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    sourcePath: path, // Save original path
  };

  // Get target collection
  const targetCollection = getTargetCollection(classification);

  if (CONFIRM) {
    // Perform the actual copy with merge
    await targetCollection.doc(id).set(normalizedData, { merge: true });
    console.log(`✅ Copied: ${path} → ${targetCollection.path}/${id}`);
  } else {
    // Dry run - just show what would happen
    console.log(`🔄 Would copy: ${path} → ${targetCollection.path}/${id}`);
    console.log(`   Classification: ${classification}`);
    console.log(`   Normalized courseType: ${normalizedData.courseType}`);
    console.log(`   Normalized department: ${normalizedData.department}`);
    console.log('');
  }
}

async function main() {
  console.log('🚀 Starting Firestore feedback consolidation');
  if (CONFIRM) {
    console.log('⚠️  WRITE MODE ENABLED - Data will be modified');
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

    console.log(`\n📄 Found ${feedbackDocuments.length} feedback documents`);
    console.log(`   - מדריכים: ${classificationStats.madrichim}`);
    console.log(`   - הגנה 474: ${classificationStats.defense474}`);
    console.log(`   - כללי: ${classificationStats.general}`);

    // Step 2: Copy and normalize each document
    console.log('\n🔄 Processing documents...');
    for (const docInfo of feedbackDocuments) {
      await copyToTarget(docInfo);
    }

  } catch (error) {
    console.error('❌ Error during consolidation:', error);
    process.exit(1);
  }

  // Step 3: Print final report
  console.log('\n' + '='.repeat(60));
  console.log('📊 FINAL REPORT');
  console.log('='.repeat(60));

  console.log(`\n📋 Documents processed: ${feedbackDocuments.length}`);
  console.log(`   - הועתקו למדריכים: ${classificationStats.madrichim}`);
  console.log(`   - הועתקו להגנה 474: ${classificationStats.defense474}`);
  console.log(`   - הועתקו למשובים כלליים: ${classificationStats.general}`);

  console.log('\n📂 Source paths:');
  Array.from(sourcePaths).sort().forEach(path => {
    console.log(`  - ${path}`);
  });

  console.log('\n🔧 Normalized values:');
  if (normalizationChanges.length > 0) {
    normalizationChanges.forEach(change => {
      console.log(`  - ${change}`);
    });
  } else {
    console.log('  (no values were normalized)');
  }

  if (CONFIRM) {
    console.log('\n✅ Consolidation completed successfully!');
    console.log('All feedback documents have been copied to organized collections.');
    console.log('Original documents remain unchanged.');
  } else {
    console.log('\n🔒 Dry run completed.');
    console.log('Review the output above and set CONFIRM = true to perform actual consolidation.');
  }

  process.exit(0);
}

// Run the consolidation
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});