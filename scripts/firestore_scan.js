// Firestore Full Scan Script - READ-ONLY
// Scans all collections and subcollections related to feedbacks
// Prereqs: place serviceAccount.json one level above this file (project root).

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Collections to scan (root level)
const COLLECTIONS_TO_SCAN = ['feedbacks', 'users', 'instructor_course_feedbacks'];

let allPaths = [];
let pathDocumentCounts = {};
let uniqueCourseTypes = new Set();
let uniqueDepartments = new Set();

// Recursive function to scan collections and subcollections
async function scanCollection(collectionRef, currentPath = '') {
  const path = currentPath ? `${currentPath}/${collectionRef.id}` : collectionRef.id;
  console.log(`\n🔍 Scanning collection: ${path}`);

  try {
    const snapshot = await collectionRef.get();
    console.log(`📄 Found ${snapshot.docs.length} documents in ${path}`);

    if (!allPaths.includes(path)) {
      allPaths.push(path);
    }
    pathDocumentCounts[path] = snapshot.docs.length;

    // Process each document
    for (const doc of snapshot.docs) {
      const docPath = `${path}/${doc.id}`;
      console.log(`\n📋 Document: ${docPath}`);
      console.log('Fields:');

      const data = doc.data();
      for (const [key, value] of Object.entries(data)) {
        console.log(`  ${key}: ${JSON.stringify(value)}`);

        // Collect unique values
        if (key === 'courseType' && value) {
          uniqueCourseTypes.add(value);
        }
        if (key === 'department' && value) {
          uniqueDepartments.add(value);
        }
      }

      // Check for subcollections
      const subcollections = await doc.listCollections();
      for (const subcollection of subcollections) {
        await scanCollection(subcollection, docPath);
      }
    }
  } catch (error) {
    console.error(`❌ Error scanning ${path}:`, error.message);
  }
}

async function main() {
  console.log('🚀 Starting Firestore full scan (READ-ONLY mode)');
  console.log('=' .repeat(50));

  try {
    // Scan root collections
    for (const collectionName of COLLECTIONS_TO_SCAN) {
      const collectionRef = db.collection(collectionName);
      await scanCollection(collectionRef);
    }

    // Also try to list all root collections (in case we missed some)
    console.log('\n🔍 Listing all root collections...');
    const allCollections = await db.listCollections();
    for (const collection of allCollections) {
      if (!COLLECTIONS_TO_SCAN.includes(collection.id)) {
        console.log(`Found additional collection: ${collection.id}`);
        await scanCollection(collection);
      }
    }

  } catch (error) {
    console.error('❌ Error during scan:', error);
  }

  // Print summary
  console.log('\n' + '='.repeat(50));
  console.log('📊 SUMMARY');
  console.log('='.repeat(50));

  console.log('\n📂 All paths found:');
  allPaths.forEach(path => {
    console.log(`  - ${path} (${pathDocumentCounts[path] || 0} documents)`);
  });

  console.log('\n📈 Document counts by path:');
  Object.entries(pathDocumentCounts).forEach(([path, count]) => {
    console.log(`  ${path}: ${count} documents`);
  });

  console.log('\n🏷️  Unique courseType values:');
  if (uniqueCourseTypes.size > 0) {
    Array.from(uniqueCourseTypes).forEach(type => {
      console.log(`  - ${type}`);
    });
  } else {
    console.log('  (none found)');
  }

  console.log('\n🏢 Unique department values:');
  if (uniqueDepartments.size > 0) {
    Array.from(uniqueDepartments).forEach(dept => {
      console.log(`  - ${dept}`);
    });
  } else {
    console.log('  (none found)');
  }

  console.log('\n✅ Scan completed successfully!');
  console.log('Note: This script only reads data and does not modify anything.');

  process.exit(0);
}

// Run the scan
main().catch(error => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});