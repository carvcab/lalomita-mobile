import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration for Variedades La Lomita.
/// Android uses google-services.json credentials; web matches the PC app.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDAY3VZDEDtM5tLP54RsR03VAnXHEJJmrk',
    appId: '1:169416079791:android:22e0f949fdb9656842975a',
    messagingSenderId: '169416079791',
    projectId: 'variedades-la-lomita',
    storageBucket: 'variedades-la-lomita.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCdIejGnwlpWbT_dsrr9zgE4iy6CfAUak4',
    appId: '1:169416079791:web:89df69c6eafbfa7842975a',
    messagingSenderId: '169416079791',
    projectId: 'variedades-la-lomita',
    authDomain: 'variedades-la-lomita.firebaseapp.com',
    storageBucket: 'variedades-la-lomita.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCdIejGnwlpWbT_dsrr9zgE4iy6CfAUak4',
    appId: '1:169416079791:web:89df69c6eafbfa7842975a',
    messagingSenderId: '169416079791',
    projectId: 'variedades-la-lomita',
    authDomain: 'variedades-la-lomita.firebaseapp.com',
    storageBucket: 'variedades-la-lomita.firebasestorage.app',
  );
}
