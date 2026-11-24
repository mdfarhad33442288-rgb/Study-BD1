import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // System tray displays notification messages automatically.
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationChannel(
    'studybd_default',
    'Study BD',
    description: 'Books, exams, courses and live class alerts',
    importance: Importance.high,
  );

  /// Never throws: a notification problem must not crash the app.
  Future<void> init(String uid) async {
    try {
      await _init(uid);
    } catch (e) {
      debugPrint('Notification setup failed: $e');
    }
  }

  Future<void> _init(String uid) async {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(); // Android 13+ runtime permission
    await fcm.subscribeToTopic('all');

    if (!_ready) {
      await _local.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        _local.show(
          n.hashCode,
          n.title,
          n.body,
          NotificationDetails(
            android: AndroidNotificationDetails(_channel.id, _channel.name, importance: Importance.high, priority: Priority.high),
          ),
        );
      });
      _ready = true;
    }

    final token = await fcm.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmToken': token}).catchError((_) {});
    }
    fcm.onTokenRefresh.listen((t) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmToken': t}).catchError((_) {});
    });
  }

  Future<void> subscribeCourse(String courseId, {bool on = true}) async {
    final f = FirebaseMessaging.instance;
    on ? await f.subscribeToTopic('course_$courseId') : await f.unsubscribeFromTopic('course_$courseId');
  }
}
