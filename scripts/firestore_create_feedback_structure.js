// Firestore Create Feedback Structure Script
// Creates a clean hierarchical structure for feedback collections

const admin = require("firebase-admin");

// Initialize Firebase Admin
// Note: serviceAccount.json should be in the project root
const serviceAccount = require("../serviceAccount.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Structure to create
const STRUCTURE = {
  feedback_general: {
    type: "collection",
    meta: { description: "משוב כללי", category: "general" }
  },
  feedback_defense_474: {
    type: "collection",
    subcollections: {
      open_circle: { description: "מעגל פתוח", category: "defense" },
      breach: { description: "פריצה", category: "defense" },
      street_scans: { description: "סריקות רחוב", category: "defense" }
    }
  },
  feedback_miyunim_madrichim: {
    type: "collection",
    meta: { description: "מיונים לקורס מדריכים", category: "madrichim" }
  }
};

// Function to create meta document
async function createMetaDocument(path, metaData) {
  try {
    const docRef = db.doc(path);
    const data = {
      ...metaData,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      version: "1.0"
    };
    await docRef.set(data);
    console.log(`✅ Created: ${path}`);
    return true;
  } catch (error) {
    console.error(`❌ Error creating ${path}:`, error.message);
    return false;
  }
}

// Function to check if document exists
async function documentExists(path) {
  try {
    const docRef = db.doc(path);
    const doc = await docRef.get();
    return doc.exists;
  } catch (error) {
    return false;
  }
}

async function main() {
  console.log("🚀 Creating Firestore feedback structure...");

  try {
    // Create feedback_general
    const generalPath = "feedback_general/_meta";
    if (!(await documentExists(generalPath))) {
      await createMetaDocument(generalPath, STRUCTURE.feedback_general.meta);
    } else {
      console.log(`📁 Exists: ${generalPath}`);
    }

    // Create feedback_defense_474 and subcollections
    const defenseBase = "feedback_defense_474";
    for (const [subName, subMeta] of Object.entries(STRUCTURE.feedback_defense_474.subcollections)) {
      const subPath = `${defenseBase}/${subName}/_meta`;
      if (!(await documentExists(subPath))) {
        await createMetaDocument(subPath, subMeta);
      } else {
        console.log(`📁 Exists: ${subPath}`);
      }
    }

    // Create feedback_miyunim_madrichim
    const miyunimPath = "feedback_miyunim_madrichim/_meta";
    if (!(await documentExists(miyunimPath))) {
      await createMetaDocument(miyunimPath, STRUCTURE.feedback_miyunim_madrichim.meta);
    } else {
      console.log(`📁 Exists: ${miyunimPath}`);
    }

  } catch (error) {
    console.error("❌ Error during structure creation:", error);
    process.exit(1);
  }

  console.log("Feedback structure created successfully");
  process.exit(0);
}

// Run the script
main().catch(error => {
  console.error("💥 Fatal error:", error);
  process.exit(1);
});