import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'secure_id_manager.dart';
import '../api/dio_client.dart';
import '../one_auth_impl.dart';
import 'env.dart';

/// Default Firebase Options configured for OneAuth SDK
const defaultOneAuthFirebaseOptions = FirebaseOptions(
  apiKey: Env.firebaseApiKey,
  appId: Env.firebaseAppId,
  messagingSenderId: Env.firebaseMessagingSenderId,
  projectId: Env.firebaseProjectId,
);

const AndroidNotificationChannel _highImportanceChannel = AndroidNotificationChannel(
  'one_auth_high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important transaction challenge notifications.',
  importance: Importance.max,
);

const List<AndroidNotificationAction> _pushApprovalActions = <AndroidNotificationAction>[
  AndroidNotificationAction(
    'action_yes',
    'YES',
    showsUserInterface: true,
    cancelNotification: true,
  ),
  AndroidNotificationAction(
    'action_no',
    'NO',
    showsUserInterface: true,
    cancelNotification: true,
  ),
];

/// Logs the complete raw FCM RemoteMessage object
void _logRawRemoteMessage(RemoteMessage message, String source) {
  if (!kDebugMode) return;
  debugPrint('==================== OneAuth Raw FCM Message ($source) ====================');
  debugPrint('Message ID   : ${message.messageId}');
  debugPrint('From         : ${message.from}');
  debugPrint('Sent Time    : ${message.sentTime}');
  debugPrint('Collapse Key : ${message.collapseKey}');
  debugPrint('TTL          : ${message.ttl}');
  debugPrint('Notification : Title="${message.notification?.title}", Body="${message.notification?.body}"');
  debugPrint('Data Payload : ${message.data}');
  debugPrint('===========================================================================');
}

/// Determines whether an incoming data payload represents a YES/NO push-approval challenge.
bool _isPushApproval(Map<String, dynamic> data) {
  return data['authenticationType'] == 'PUSH' ||
      data['preferredAuthenticationType'] == 'PUSH' ||
      data['authType'] == 'PUSH' ||
      data['prompt'] == 'YES_NO' ||
      data['options'] == 'YES,NO' ||
      data.containsKey('txnId') ||
      data.containsKey('customerUniqueKey');
}

/// Parses a notification-response payload string into a data map.
Map<String, dynamic> _decodePayload(String? payload) {
  if (payload == null || payload.isEmpty) return {};
  try {
    return jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

/// Shared handler for a tapped YES/NO notification action, used by every
/// entry point (foreground, background isolate, and background-tap-to-open).
Future<void> _handleChallengeAction(String? actionId, String? payload) async {
  final normalized = actionId?.toLowerCase() ?? '';
  if (normalized != 'action_yes' && normalized != 'action_no') return;

  final data = _decodePayload(payload);
  final messageId = data['messageId'] ?? data['message_id'] ?? data['customerUniqueKey'];
  final txnId = data['txnId'] ?? data['txn_id'] ?? data['transactionId'];
  final txnHash = data['txnHash'] ?? data['txn_hash'] ?? '';
  final isYes = normalized == 'action_yes';
  final hasTxn = txnId != null && txnId.toString().isNotEmpty;

  debugPrint(
    'OneAuth: ${isYes ? "YES" : "NO"} tapped for '
        '${hasTxn ? "txnId: $txnId" : "messageId: $messageId"}. '
        'Invoking ${hasTxn ? "submitTransactionSignature" : "verifyNumberMatching"}...',
  );

  if (!isYes) {
    OneAuth().notifyChallengeReceived({
      'status': 'DECLINED',
      if (hasTxn) 'txnId': txnId,
      'messageId': messageId,
      'userResponse': 'false',
    });
  }

  try {
    if (hasTxn) {
      await OneAuth().submitTransactionSignature(
        txnId: txnId.toString(),
        txnHash: txnHash.toString(),
        pin: isYes ? 'PUSH_APPROVED' : 'PUSH_DECLINED',
        authType: 'PUSH',
        userResponse: isYes.toString(),
      );
    } else {
      await OneAuth().verifyNumberMatching(
        messageId: messageId?.toString(),
        preferredAuthenticationType: 'PUSH',
        userResponse: isYes.toString(),
      );
    }
    debugPrint('OneAuth: ${isYes ? "YES" : "NO"} action completed successfully.');
  } catch (e) {
    debugPrint('OneAuth: ${isYes ? "YES" : "NO"} action failed: $e');
  }
}

/// Builds the platform notification details for a challenge push, reusing the
/// shared high-importance channel and YES/NO actions when applicable.
NotificationDetails _buildChallengeNotificationDetails(Map<String, dynamic> data) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      _highImportanceChannel.id,
      _highImportanceChannel.name,
      channelDescription: _highImportanceChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_one_auth_notification',
      actions: _isPushApproval(data) ? _pushApprovalActions : null,
    ),
  );
}

/// Top-level entry point required by flutter_local_notifications for handling
/// a notification-action tap while the app is backgrounded/terminated.
@pragma('vm:entry-point')
void _oneAuthBackgroundNotificationResponseHandler(NotificationResponse response) {
  _handleChallengeAction(response.actionId, response.payload);
}

/// Isolated Top-Level Background Message Handler required by FCM
@pragma('vm:entry-point')
Future<void> _oneAuthBackgroundMessageHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: defaultOneAuthFirebaseOptions);
  }
  _logRawRemoteMessage(message, 'Background');

  // Trigger local notification for background data-only payloads
  if (message.notification == null && message.data.isNotEmpty) {
    try {
      final localNotifications = FlutterLocalNotificationsPlugin();
      const androidInitSettings = AndroidInitializationSettings('ic_one_auth_notification');
      const initSettings = InitializationSettings(android: androidInitSettings);
      await localNotifications.initialize(
        initSettings,
        onDidReceiveBackgroundNotificationResponse: _oneAuthBackgroundNotificationResponseHandler,
      );

      final title = message.data['title'] ?? 'OneAuth Challenge';
      final body = message.data['body'] ?? message.data['message'] ?? 'Approve login request?';

      await localNotifications.show(
        message.hashCode,
        title,
        body,
        _buildChallengeNotificationDetails(message.data),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('OneAuth SDK: Background Local Notification error: $e');
    }
  }
}

/// Manages all Firebase Cloud Messaging (FCM) operations for the OneAuth SDK.
class OneAuthPushManager {
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _challengeStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  Map<String, dynamic>? _latestChallengeData;

  /// Stream of incoming transaction challenge push notification payloads
  Stream<Map<String, dynamic>> get onPushChallengeReceived =>
      _challengeStreamController.stream;

  /// Retrieves the most recent push challenge payload received by the SDK.
  Map<String, dynamic>? get latestChallengeData => _latestChallengeData;

  /// Initializes FCM, requests permissions, and sets up notification listeners internally.
  Future<void> initialize({
    required DioClient dioClient,
    FirebaseOptions? firebaseOptions,
  }) async {
    try {
      // 1. Initialize Firebase if not already initialized by host application
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: firebaseOptions ?? defaultOneAuthFirebaseOptions,
        );
      }

      // 2. Request Push Permissions automatically
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('OneAuth SDK: Push notification permissions not granted.');
        return;
      }

      // 3. Initialize Local Notifications Plugin & High Importance Channel
      const androidInitSettings = AndroidInitializationSettings('ic_one_auth_notification');
      const initSettings = InitializationSettings(android: androidInitSettings);
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('OneAuth: Local Notification tapped: actionId=${response.actionId}, payload=${response.payload}');
          _handleChallengeAction(response.actionId, response.payload);
        },
        onDidReceiveBackgroundNotificationResponse: _oneAuthBackgroundNotificationResponseHandler,
      );

      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_highImportanceChannel);

      // Enable heads-up notification banners when app is open in Foreground
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Register Top-Level Background Handler
      FirebaseMessaging.onBackgroundMessage(_oneAuthBackgroundMessageHandler);

      // 5. Sync FCM Token with OneAuth Server
      await syncFcmToken(dioClient);

      // 6. Auto-sync on Token Refresh
      _fcm.onTokenRefresh.listen((newToken) async {
        debugPrint('OneAuth SDK: FCM Token refreshed.');
        await _secureStorage.write(key: 'fcm_token', value: newToken);
        await _uploadToken(dioClient, newToken);
      });

      // 7. Foreground Push Handler (Triggers local heads-up banner)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logRawRemoteMessage(message, 'Foreground');

        final notification = message.notification;
        final title = notification?.title ?? message.data['title'] ?? 'OneAuth Challenge';
        final body = notification?.body ?? message.data['body'] ?? message.data['message'] ?? 'Approve login request?';

        _localNotifications.show(
          message.hashCode,
          title,
          body,
          _buildChallengeNotificationDetails(message.data),
          payload: jsonEncode(message.data),
        );

        _processPushData(message.data);
      });

      // 8. Background Notification Tap Handler
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _logRawRemoteMessage(message, 'Opened from Background');
        _processPushData(message.data);
      });

      // 9. Terminated App Launch Handler
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _logRawRemoteMessage(initialMessage, 'Launched from Terminated');
        _processPushData(initialMessage.data);
      }
    } catch (e) {
      debugPrint('OneAuth SDK: FCM Push Initialization failed or skipped: $e');
    }
  }

  /// Retrieves the stored FCM token or fetches a fresh one from Firebase Messaging and stores it.
  @Deprecated('Use getFcmToken() instead.')
  Future<String?> getOrCreateFcmToken() async => getFcmToken();

  /// Retrieves current FCM Token from FCM and stores it securely for later use.
  /// Falls back to the last stored token if a fresh fetch fails.
  Future<String?> getFcmToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await _secureStorage.write(key: 'fcm_token', value: token);
        return token;
      }
    } catch (e) {
      debugPrint('OneAuth SDK: Failed to get fresh FCM token: $e');
    }
    return await getStoredFcmToken();
  }

  /// Retrieves the stored FCM token from secure storage.
  Future<String?> getStoredFcmToken() async {
    return await _secureStorage.read(key: 'fcm_token');
  }

  Future<void> syncFcmToken(DioClient dioClient) async {
    final token = await getFcmToken();
    if (token != null && token.isNotEmpty) {
      await _uploadToken(dioClient, token);
    }
  }

  Future<void> _uploadToken(DioClient dioClient, String fcmToken) async {
    try {
      final deviceUuid = await OneAuthSecureIdManager.getOrCreateDeviceUuid();
      await dioClient.dio.post(
        '/auth/device/fcm-token',
        data: {
          'fcmToken': fcmToken,
          'deviceUuid': deviceUuid,
        },
      );
      debugPrint('OneAuth SDK: FCM token synced with server (deviceUuid: $deviceUuid).');
    } catch (e) {
      debugPrint('OneAuth SDK: Failed to sync FCM token to server: $e');
    }
  }

  void _processPushData(Map<String, dynamic> data) {
    if (data.isEmpty) {
      debugPrint('OneAuth SDK: Data payload is empty. If testing from Firebase Console, add Key-Value pairs under "Additional options -> Custom data" (e.g. txnId, txnHash).');
      return;
    }

    if (data.containsKey('txnId') ||
        data.containsKey('txnHash') ||
        data.containsKey('numberMatchingCode') ||
        data.containsKey('action') ||
        data.containsKey('authenticationType')) {
      debugPrint('OneAuth SDK: Emitting FCM Challenge Payload.');
      _latestChallengeData = data;
      _challengeStreamController.add(data);
    }
  }

  void notifyChallengeReceived(Map<String, dynamic> data) {
    debugPrint('OneAuth SDK: Emitting Notification/Verify Payload.');
    _latestChallengeData = data;
    _challengeStreamController.add(data);
  }

  void dispose() {
    _challengeStreamController.close();
  }
}