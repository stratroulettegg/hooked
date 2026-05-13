import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Projekt nutzt eine named Firestore-Datenbank `default`.
FirebaseFirestore get _firestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'default',
    );

/// Verwaltet den FCM-Token des aktuellen Users in Firestore und sorgt
/// dafür, dass Token-Refreshes serverseitig sichtbar werden.
///
/// Schema: `userProfiles/{uid}/fcmTokens/{token}` mit
/// `{ platform, createdAt, lastSeenAt }`.
class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  StreamSubscription<String>? _refreshSub;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  String? _currentToken;
  String? _currentUid;

  Future<void> init() async {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChange,
    );
    _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      _currentToken = t;
      _saveCurrentToken();
    });
    // Foreground-Push: FCM zeigt im Foreground keine Banner — wir
    // wandeln das in eine lokale Notification auf dem "social"-Channel um.
    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_onForeground);
    // iOS: erlaubt Banner trotz Foreground.
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    } catch (_) {}
  }

  void _onForeground(RemoteMessage m) {
    final n = m.notification;
    final title = n?.title ?? m.data['title']?.toString();
    final body = n?.body ?? m.data['body']?.toString();
    if (title == null && body == null) return;
    final threadId = m.data['threadId']?.toString();
    NotificationService.instance.showSocialPush(
      title: title ?? 'Hooked',
      body: body ?? '',
      threadId: threadId,
      payload: m.data['postId']?.toString(),
    );
  }

  /// Fragt die System-Push-Permission ab (iOS Dialog / Android 13+ Dialog).
  Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      if (kDebugMode) debugPrint('FCM requestPermission failed: $e');
      return false;
    }
  }

  /// Holt den aktuellen FCM-Token und persistiert ihn unter dem User.
  /// Idempotent — kann beliebig oft aufgerufen werden.
  Future<void> registerToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // iOS braucht das APNS-Token, bevor FCM eines liefern kann.
      // Es kann kurz nach dem App-Start noch nicht gesetzt sein → bis zu
      // 3 Versuche mit je 2 s Wartezeit.
      if (Platform.isIOS) {
        String? apns;
        for (int i = 0; i < 3; i++) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null && apns.isNotEmpty) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        if (apns == null || apns.isEmpty) {
          // APNS token nicht verfügbar — still überspringen.
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      _currentUid = user.uid;
      await _saveCurrentToken();
    } catch (e) {
      if (kDebugMode) debugPrint('FCM registerToken failed: $e');
    }
  }

  /// Token aus Firestore entfernen (z.B. bei Logout).
  Future<void> clearForUser(String uid) async {
    final t = _currentToken;
    if (t == null) return;
    try {
      await _firestore
          .collection('userProfiles')
          .doc(uid)
          .collection('fcmTokens')
          .doc(t)
          .delete();
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _handleAuthChange(User? user) async {
    if (user == null) {
      final oldUid = _currentUid;
      if (oldUid != null) await clearForUser(oldUid);
      _currentUid = null;
      return;
    }
    _currentUid = user.uid;
    await registerToken();
  }

  Future<void> _saveCurrentToken() async {
    final uid = _currentUid ?? FirebaseAuth.instance.currentUser?.uid;
    final token = _currentToken;
    if (uid == null || token == null) return;
    try {
      await _firestore
          .collection('userProfiles')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
            'platform': Platform.isIOS ? 'ios' : 'android',
            'createdAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('FCM saveToken failed: $e');
    }
  }
}
