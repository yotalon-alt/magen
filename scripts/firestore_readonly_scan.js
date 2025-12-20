// Firestore READ-ONLY Full Scan Script
// Scans all collections and subcollections, identifies feedback documents by content
// READ-ONLY: No write, update, set, or delete operations performed
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// READ-ONLY MODE - NO MODIFICATIONS ALLOWED
console.log('🔒 READ-ONLY MODE: This script only reads data and does not modify anything.');

// Data collection
let feedbackDocuments = [];
let allPaths = new Set();
let uniqueCourseTypes = new Set();
let uniqueDepartments = new Set();

// Function to check if a document looks like a feedback document
function isFeedbackDocument(data) {
  // Check for typical feedback fields
  const feedbackIndicators = [
    'scores',
    'instructorName',
    'folder',
    'exercise',
    'role',
    'name',
    'notes',
    'criteriaList',
    'commandText',
    'scenario',
    'settlement',
    'attendeesCount'
  ];

  // Must have at least 3 feedback indicators
  let indicatorCount = 0;
  for (const field of feedbackIndicators) {
    if (data.hasOwnProperty(field)) {
      indicatorCount++;
    }
  }

  return indicatorCount >= 3;
}

// Recursive function to scan all collections and subcollections
async function scanAllCollections(collectionRef, currentPath = '') {
  const path = currentPath ? `${currentPath}/${collectionRef.id}` : collectionRef.id;

  try {
    const snapshot = await collectionRef.get();
    allPaths.add(path);

    console.log(`\n🔍 Scanning collection: ${path} (${snapshot.docs.length} documents)`);

    // Process each document
    for (const doc of snapshot.docs) {
      const docPath = `${path}/${doc.id}`;
      const data = doc.data();

      // Check if this is a feedback document
      if (isFeedbackDocument(data)) {
        console.log(`\n📋 FEEDBACK DOCUMENT FOUND:`);
        console.log(`   Path: ${docPath}`);
        console.log(`   ID: ${doc.id}`);
        console.log(`   Fields:`);

        feedbackDocuments.push({
          path: docPath,
          id: doc.id,
          data: data
        });

        // Print all fields and values
        for (const [key, value] of Object.entries(data)) {
          console.log(`     ${key}: ${JSON.stringify(value, null, 2)}`);

          // Collect unique values
          if (key === 'courseType' && value) {
            uniqueCourseTypes.add(String(value));
          }
          if (key === 'department' && value) {
            uniqueDepartments.add(String(value));
          }
        }

        console.log(`   ---`);
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
  console.log('🚀 Starting Firestore READ-ONLY full scan');
  console.log('🔍 Scanning ALL collections and subcollections for feedback documents');
  console.log('=' .repeat(60));

  try {
    // Get all root collections
    console.log('📂 Getting all root collections...');
    const rootCollections = await db.listCollections();

    console.log(`Found ${rootCollections.length} root collections:`);
    rootCollections.forEach(col => console.log(`  - ${col.id}`));

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

  console.log('\n📂 Documents found in paths:');
  const pathCounts = {};
  feedbackDocuments.forEach(doc => {
    const path = doc.path.split('/').slice(0, -1).join('/'); // Remove document ID
    pathCounts[path] = (pathCounts[path] || 0) + 1;
  });

  Object.entries(pathCounts).forEach(([path, count]) => {
    console.log(`  ${path}: ${count} documents`);
  });

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

  console.log('\n📋 All paths scanned:');
  Array.from(allPaths).sort().forEach(path => {
    console.log(`  - ${path}`);
  });

  console.log('\n✅ READ-ONLY scan completed successfully!');
  console.log('🔒 No data was modified during this scan.');

  process.exit(0);
}

// Run the scan
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});