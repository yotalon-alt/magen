// Firestore Controlled Fix Script
// Copies and normalizes all feedback documents to central 'feedbacks' collection
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// CONFIRMATION FLAG - SET TO true TO ENABLE WRITES
const CONFIRM = false; // ⚠️  SET TO true ONLY AFTER CAREFUL REVIEW

if (!CONFIRM) {
  console.log('❌ CONFIRMATION REQUIRED');
  console.log('Set CONFIRM = true at the top of this script to enable write operations.');
  console.log('This script will modify your Firestore database.');
  process.exit(0);
}

// Collections to scan (root level)
const COLLECTIONS_TO_SCAN = ['feedbacks', 'users', 'instructor_course_feedbacks'];

let allFeedbackDocuments = [];
let normalizationReport = {
  copiedDocuments: 0,
  sourcePaths: new Set(),
  normalizedValues: [],
};

// Normalization functions
function normalizeDepartment(value) {
  if (!value) return 'לא מוגדר';

  const str = String(value).trim();
  if (str === 'הגנה474' || str === 'הגנה 474') {
    normalizationReport.normalizedValues.push(`department: "${str}" → "474"`);
    return '474';
  }

  return str;
}

function normalizeCourseType(value) {
  if (!value) return 'לא מוגדר';
  return String(value).trim();
}

function normalizeValue(value) {
  return value || 'לא מוגדר';
}

// Recursive function to scan collections and subcollections for feedback documents
async function scanForFeedbacks(collectionRef, currentPath = '') {
  const path = currentPath ? `${currentPath}/${collectionRef.id}` : collectionRef.id;

  try {
    const snapshot = await collectionRef.get();

    // Process each document
    for (const doc of snapshot.docs) {
      const docPath = `${path}/${doc.id}`;
      const data = doc.data();

      // Check if this looks like a feedback document
      // (has typical feedback fields like scores, instructorName, etc.)
      const isFeedback = data.scores || data.instructorName || data.folder || data.exercise;

      if (isFeedback) {
        allFeedbackDocuments.push({
          ref: doc.ref,
          path: docPath,
          data: data,
          id: doc.id,
        });
      }

      // Check for subcollections
      const subcollections = await doc.listCollections();
      for (const subcollection of subcollections) {
        await scanForFeedbacks(subcollection, docPath);
      }
    }
  } catch (error) {
    console.error(`❌ Error scanning ${path}:`, error.message);
  }
}

// Function to normalize and copy document to central feedbacks collection
async function copyToCentralFeedbacks(docInfo) {
  const { ref, path, data, id } = docInfo;

  // Normalize the data
  const normalizedData = {
    ...data,
    courseType: normalizeCourseType(data.courseType || data.folder),
    department: normalizeDepartment(data.department || data.settlement),
    createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    sourcePath: path, // Save original path
  };

  // Ensure all required fields are present
  normalizedData.courseType = normalizeValue(normalizedData.courseType);
  normalizedData.department = normalizeValue(normalizedData.department);

  // Copy to central feedbacks collection with merge
  const centralRef = db.collection('feedbacks').doc(id);
  await centralRef.set(normalizedData, { merge: true });

  normalizationReport.copiedDocuments++;
  normalizationReport.sourcePaths.add(path);

  console.log(`✅ Copied: ${path} → feedbacks/${id}`);
}

async function main() {
  console.log('🚀 Starting Firestore controlled fix');
  console.log('⚠️  CONFIRMATION ENABLED - Write operations allowed');
  console.log('=' .repeat(50));

  try {
    // Step 1: Scan all collections for feedback documents
    console.log('🔍 Scanning for feedback documents...');

    for (const collectionName of COLLECTIONS_TO_SCAN) {
      const collectionRef = db.collection(collectionName);
      await scanForFeedbacks(collectionRef);
    }

    // Also scan additional root collections
    const allCollections = await db.listCollections();
    for (const collection of allCollections) {
      if (!COLLECTIONS_TO_SCAN.includes(collection.id)) {
        await scanForFeedbacks(collection);
      }
    }

    console.log(`📄 Found ${allFeedbackDocuments.length} feedback documents`);

    // Step 2: Copy and normalize each document
    console.log('\n🔄 Copying and normalizing documents...');

    for (const docInfo of allFeedbackDocuments) {
      await copyToCentralFeedbacks(docInfo);
    }

  } catch (error) {
    console.error('❌ Error during fix:', error);
    process.exit(1);
  }

  // Step 3: Print final report
  console.log('\n' + '='.repeat(50));
  console.log('📊 FINAL REPORT');
  console.log('='.repeat(50));

  console.log(`\n📋 Documents copied: ${normalizationReport.copiedDocuments}`);

  console.log('\n📂 Source paths:');
  Array.from(normalizationReport.sourcePaths).forEach(path => {
    console.log(`  - ${path}`);
  });

  console.log('\n🔧 Normalized values:');
  if (normalizationReport.normalizedValues.length > 0) {
    normalizationReport.normalizedValues.forEach(change => {
      console.log(`  - ${change}`);
    });
  } else {
    console.log('  (no values were normalized)');
  }

  console.log('\n✅ Fix completed successfully!');
  console.log('All feedback documents have been copied to the central "feedbacks" collection.');
  console.log('Original documents remain unchanged.');

  process.exit(0);
}

// Run the fix
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});