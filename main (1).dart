import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/services/ads_service.dart';
import 'core/services/notification_service.dart';

bool _firebaseReady = false;

/// Logs an error and forwards it to Crashlytics when Firebase is up.
/// Never throws, so reporting can not cause a second crash.
void _report(Object error, StackTrace? stack, {bool fatal = false}) {
  debugPrint('Study BD error: $error\n$stack');
  if (!_firebaseReady || kDebugMode) return;
  try {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  } catch (_) {}
}

Future<void> main() async {
  // Everything (binding, runApp) must run in the same zone.
  await runZonedGuarded<Future<void>>(_bootstrap, (e, s) => _report(e, s));
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    _report(e, s);
    return true; // handled: do not kill the app
  };

  // A widget that throws while building shows a readable message instead of a blank screen.
  ErrorWidget.builder = (details) => Material(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Something went wrong on this screen.\n\n${details.exceptionAsString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

  // Firebase reads android/app/google-services.json. If that file is missing or
  // wrong, show the reason on screen instead of crashing.
  try {
    await Firebase.initializeApp();
    _firebaseReady = true;
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 100 * 1024 * 1024);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  } catch (e, s) {
    _report(e, s, fatal: true);
    runApp(StartupErrorApp(
      title: 'Firebase could not start',
      message: 'Check that android/app/google-services.json belongs to this app '
          '(package com.studybd.app) and rebuild.\n\n$e',
    ));
    return;
  }

  // Ads must never block or break startup.
  unawaited(AdsService.instance.init().catchError((Object e, StackTrace s) => _report(e, s)));

  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e, s) {
    _report(e, s, fatal: true);
    runApp(StartupErrorApp(title: 'Storage error', message: '$e'));
    return;
  }

  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const StudyBdApp(),
  ));
}

/// Shown only when the app can not start. Text is selectable so it can be copied.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.title, required this.message});
  final String title, message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  SelectableText(message),
                ]),
              ),
            ),
          ),
        ),
      );
}
