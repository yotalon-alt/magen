// Placeholder Firebase options file for web and other platforms.
// Replace the apiKey, authDomain, projectId, etc. with your Firebase project's values.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // Fallback generic options for other platforms.
    return defaultOptions;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDMMhuxzewpHq_hW621sS-pxPdCdVdH-AY',
    authDomain: 'ravshtz.firebaseapp.com',
    projectId: 'ravshtz',
    storageBucket: 'ravshtz.firebasestorage.app',
    messagingSenderId: '571636372034',
    appId: '1:571636372034:web:81c30297468c6d447493db',
  );

  static const FirebaseOptions defaultOptions = FirebaseOptions(
    apiKey: 'AIzaSyDMMhuxzewpHq_hW621sS-pxPdCdVdH-AY',
    appId: '1:571636372034:web:81c30297468c6d447493db',
    messagingSenderId: '571636372034',
    projectId: 'ravshtz',
  );
}
