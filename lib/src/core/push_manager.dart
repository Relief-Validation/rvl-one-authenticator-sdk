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

/// Logs the complete raw FCM RemoteMessage object
void _logRawRemoteMessage(RemoteMessage message, String source) {
  debugPrint('==================== OneAuth Raw FCM Message ($source) ====================');
  debugPrint('Message ID   : ${message.messageId}');
  debugPrint('From         : ${message.from}');
  debugPrint('Sent Time    : ${message.sentTime}');
  debugPrint('Collapse Key : ${message.collapseKey}');
  debugPrint('TTL          : ${message.ttl}');
  debugPrint('Notification : Title="${message.notification?.title}", Body="${message.notification?.body}"');
  debugPrint('Data Payload : ${message.data}');
  debugPrint('Raw Map      : ${message.toMap()}');
  debugPrint('===========================================================================');
}

@pragma('vm:entry-point')
void _oneAuthBackgroundNotificationResponseHandler(NotificationResponse response) async {
  debugPrint('OneAuth: Background Notification Response tapped: actionId=${response.actionId}');
  if (response.actionId == 'action_yes' || response.actionId == 'action_no') {
    Map<String, dynamic> data = {};
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        data = jsonDecode(response.payload!) as Map<String, dynamic>;
      } catch (_) {}
    }
    final messageId = data['messageId'] ?? data['message_id'] ?? data['customerUniqueKey'];
    final txnId = data['txnId'] ?? data['txn_id'] ?? data['transactionId'];
    final txnHash = data['txnHash'] ?? data['txn_hash'] ?? '';

    if (txnId != null && txnId.toString().isNotEmpty) {
      if (response.actionId == 'action_yes') {
        debugPrint('OneAuth: Background YES tapped for txnId: $txnId. Invoking submitTransactionSignature...');
        try {
          await OneAuth().submitTransactionSignature(
            txnId: txnId.toString(),
            txnHash: txnHash.toString(),
            pin: 'PUSH_APPROVED',
            authType: 'PUSH',
            userResponse: 'true',
          );
          debugPrint('OneAuth: Background Transaction Push Verification YES succeeded!');
        } catch (e) {
          debugPrint('OneAuth: Background Transaction Push Verification YES failed: $e');
        }
      } else if (response.actionId == 'action_no') {
        debugPrint('OneAuth: Background NO tapped for txnId: $txnId. Invoking submitTransactionSignature...');
        OneAuth().notifyChallengeReceived({
          'status': 'DECLINED',
          'txnId': txnId,
          'messageId': messageId,
          'userResponse': 'false',
        });
        try {
          await OneAuth().submitTransactionSignature(
            txnId: txnId.toString(),
            txnHash: txnHash.toString(),
            pin: 'PUSH_DECLINED',
            authType: 'PUSH',
            userResponse: 'false',
          );
          debugPrint('OneAuth: Background Transaction Push Verification NO completed.');
        } catch (e) {
          debugPrint('OneAuth: Background Transaction Push Verification NO failed: $e');
        }
      }
    } else {
      if (response.actionId == 'action_yes') {
        debugPrint('OneAuth: Background YES tapped for messageId: $messageId. Invoking verifyNumberMatching...');
        try {
          await OneAuth().verifyNumberMatching(
            messageId: messageId?.toString(),
            preferredAuthenticationType: 'PUSH',
            userResponse: 'true',
          );
          debugPrint('OneAuth: Background Push Verification YES succeeded!');
        } catch (e) {
          debugPrint('OneAuth: Background Push Verification YES failed: $e');
        }
      } else if (response.actionId == 'action_no') {
        debugPrint('OneAuth: Background NO tapped for messageId: $messageId. Invoking verifyNumberMatching...');
        OneAuth().notifyChallengeReceived({
          'status': 'DECLINED',
          'messageId': messageId,
          'userResponse': 'false',
        });
        try {
          await OneAuth().verifyNumberMatching(
            messageId: messageId?.toString(),
            preferredAuthenticationType: 'PUSH',
            userResponse: 'false',
          );
          debugPrint('OneAuth: Background Push Verification NO succeeded!');
        } catch (e) {
          debugPrint('OneAuth: Background Push Verification NO failed: $e');
        }
      }
    }
  }
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
      final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
      const androidInitSettings = AndroidInitializationSettings('ic_one_auth_notification');
      const initSettings = InitializationSettings(android: androidInitSettings);
      await localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) async {
          if (response.actionId == 'action_yes' || response.actionId == 'action_no') {
            Map<String, dynamic> data = {};
            if (response.payload != null && response.payload!.isNotEmpty) {
              try {
                data = jsonDecode(response.payload!) as Map<String, dynamic>;
              } catch (_) {}
            }
            final messageId = data['messageId'] ?? data['message_id'] ?? data['customerUniqueKey'];
            final txnId = data['txnId'] ?? data['txn_id'] ?? data['transactionId'];
            final txnHash = data['txnHash'] ?? data['txn_hash'] ?? '';

            if (txnId != null && txnId.toString().isNotEmpty) {
              if (response.actionId == 'action_yes') {
                try {
                  await OneAuth().submitTransactionSignature(
                    txnId: txnId.toString(),
                    txnHash: txnHash.toString(),
                    pin: 'PUSH_APPROVED',
                    authType: 'PUSH',
                    userResponse: 'true',
                  );
                } catch (e) {
                  debugPrint('OneAuth: Background Transaction YES tap failed: $e');
                }
              } else if (response.actionId == 'action_no') {
                OneAuth().notifyChallengeReceived({
                  'status': 'DECLINED',
                  'txnId': txnId,
                  'messageId': messageId,
                  'userResponse': 'false',
                });
                try {
                  await OneAuth().submitTransactionSignature(
                    txnId: txnId.toString(),
                    txnHash: txnHash.toString(),
                    pin: 'PUSH_DECLINED',
                    authType: 'PUSH',
                    userResponse: 'false',
                  );
                } catch (e) {
                  debugPrint('OneAuth: Background Transaction NO tap failed: $e');
                }
              }
            } else {
              if (response.actionId == 'action_yes') {
                try {
                  await OneAuth().verifyNumberMatching(
                    messageId: messageId?.toString(),
                    preferredAuthenticationType: 'PUSH',
                    userResponse: 'true',
                  );
                } catch (e) {
                  debugPrint('OneAuth: Background YES tap failed: $e');
                }
              } else if (response.actionId == 'action_no') {
                OneAuth().notifyChallengeReceived({
                  'status': 'DECLINED',
                  'messageId': messageId,
                  'userResponse': 'false',
                });
                try {
                  await OneAuth().verifyNumberMatching(
                    messageId: messageId?.toString(),
                    preferredAuthenticationType: 'PUSH',
                    userResponse: 'false',
                  );
                } catch (e) {
                  debugPrint('OneAuth: Background NO tap failed: $e');
                }
              }
            }
          }
        },
        onDidReceiveBackgroundNotificationResponse: _oneAuthBackgroundNotificationResponseHandler,
      );

      final title = message.data['title'] ?? 'OneAuth Challenge';
      final body = message.data['body'] ?? message.data['message'] ?? 'Approve login request?';
      final isPushApproval = (message.data['authenticationType'] == 'PUSH' ||
                              message.data['preferredAuthenticationType'] == 'PUSH' ||
                              message.data['authType'] == 'PUSH' ||
                              message.data['prompt'] == 'YES_NO' ||
                              message.data['options'] == 'YES,NO' ||
                              message.data.containsKey('txnId') ||
                              message.data.containsKey('customerUniqueKey'));

      await localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'one_auth_high_importance_channel',
            'High Importance Notifications',
            channelDescription: 'This channel is used for important transaction challenge notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_one_auth_notification',
            actions: isPushApproval
                ? <AndroidNotificationAction>[
                    const AndroidNotificationAction(
                      'action_yes',
                      'YES',
                      showsUserInterface: true,
                      cancelNotification: true,
                    ),
                    const AndroidNotificationAction(
                      'action_no',
                      'NO',
                      showsUserInterface: true,
                      cancelNotification: true,
                    ),
                  ]
                : null,
          ),
        ),
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
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          debugPrint('OneAuth: Local Notification tapped: actionId=${response.actionId}, payload=${response.payload}');
          final actionId = response.actionId?.toLowerCase() ?? '';
          final isYes = actionId == 'action_yes' || actionId == 'yes' || actionId == 'approve';
          final isNo = actionId == 'action_no' || actionId == 'no' || actionId == 'deny' || actionId == 'decline';

          if (isYes || isNo) {
            Map<String, dynamic> data = {};
            if (response.payload != null && response.payload!.isNotEmpty) {
              try {
                data = jsonDecode(response.payload!) as Map<String, dynamic>;
              } catch (_) {}
            }
            final messageId = data['messageId'] ?? data['message_id'] ?? data['customerUniqueKey'];
            final txnId = data['txnId'] ?? data['txn_id'] ?? data['transactionId'];
            final txnHash = data['txnHash'] ?? data['txn_hash'] ?? '';

            if (txnId != null && txnId.toString().isNotEmpty) {
              if (isYes) {
                debugPrint('OneAuth: YES action tapped on notification for txnId: $txnId. Invoking submitTransactionSignature...');
                try {
                  await OneAuth().submitTransactionSignature(
                    txnId: txnId.toString(),
                    txnHash: txnHash.toString(),
                    pin: 'PUSH_APPROVED',
                    authType: 'PUSH',
                    userResponse: 'true',
                  );
                  debugPrint('OneAuth: Transaction Push Verification YES completed successfully.');
                } catch (e) {
                  debugPrint('OneAuth: Transaction Push Verification YES failed: $e');
                }
              } else if (isNo) {
                debugPrint('OneAuth: NO action tapped on notification for txnId: $txnId. Invoking submitTransactionSignature...');
                notifyChallengeReceived({
                  'status': 'DECLINED',
                  'txnId': txnId,
                  'messageId': messageId,
                  'userResponse': 'false',
                });
                try {
                  await OneAuth().submitTransactionSignature(
                    txnId: txnId.toString(),
                    txnHash: txnHash.toString(),
                    pin: 'PUSH_DECLINED',
                    authType: 'PUSH',
                    userResponse: 'false',
                  );
                  debugPrint('OneAuth: Transaction Push Verification NO completed.');
                } catch (e) {
                  debugPrint('OneAuth: Transaction Push Verification NO failed: $e');
                }
              }
            } else {
              if (isYes) {
                debugPrint('OneAuth: YES action tapped on notification for messageId: $messageId. Invoking verifyNumberMatching...');
                try {
                  await OneAuth().verifyNumberMatching(
                    messageId: messageId?.toString(),
                    preferredAuthenticationType: 'PUSH',
                    userResponse: 'true',
                  );
                  debugPrint('OneAuth: Push Verification YES completed successfully.');
                } catch (e) {
                  debugPrint('OneAuth: Push Verification YES failed: $e');
                }
              } else if (isNo) {
                debugPrint('OneAuth: NO action tapped on notification for messageId: $messageId. Invoking verifyNumberMatching...');
                notifyChallengeReceived({
                  'status': 'DECLINED',
                  'messageId': messageId,
                  'userResponse': 'false',
                });
                try {
                  await OneAuth().verifyNumberMatching(
                    messageId: messageId?.toString(),
                    preferredAuthenticationType: 'PUSH',
                    userResponse: 'false',
                  );
                  debugPrint('OneAuth: Push Verification NO completed successfully.');
                } catch (e) {
                  debugPrint('OneAuth: Push Verification NO failed: $e');
                }
              }
            }
          }
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
        debugPrint('OneAuth SDK: FCM Token refreshed: $newToken');
        await _secureStorage.write(key: 'fcm_token', value: newToken);
        await _uploadToken(dioClient, newToken);
      });

      // 7. Foreground Push Handler (Triggers local heads-up banner)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logRawRemoteMessage(message, 'Foreground');

        final notification = message.notification;
        final title = notification?.title ?? message.data['title'] ?? 'OneAuth Challenge';
        final body = notification?.body ?? message.data['body'] ?? message.data['message'] ?? 'Approve login request?';
        final isPushApproval = (message.data['authenticationType'] == 'PUSH' ||
                                message.data['preferredAuthenticationType'] == 'PUSH' ||
                                message.data['authType'] == 'PUSH' ||
                                message.data['prompt'] == 'YES_NO' ||
                                message.data['options'] == 'YES,NO' ||
                                message.data.containsKey('txnId') ||
                                message.data.containsKey('customerUniqueKey'));

        _localNotifications.show(
          message.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _highImportanceChannel.id,
              _highImportanceChannel.name,
              channelDescription: _highImportanceChannel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: 'ic_one_auth_notification',
              actions: isPushApproval
                  ? <AndroidNotificationAction>[
                      const AndroidNotificationAction(
                        'action_yes',
                        'YES',
                        showsUserInterface: true,
                        cancelNotification: true,
                      ),
                      const AndroidNotificationAction(
                        'action_no',
                        'NO',
                        showsUserInterface: true,
                        cancelNotification: true,
                      ),
                    ]
                  : null,
            ),
          ),
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
  Future<String?> getOrCreateFcmToken() async {
    return await getFcmToken();
  }

  /// Retrieves current FCM Token from FCM and stores it securely for later use.
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
    final token = await getOrCreateFcmToken();
    if (token != null && token.isNotEmpty) {
      debugPrint('OneAuth SDK: Active FCM Token: $token');
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
      debugPrint('OneAuth SDK: FCM token ($fcmToken) with deviceUuid ($deviceUuid) synced with server.');
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
      debugPrint('OneAuth SDK: Emitting FCM Challenge Payload: $data');
      _latestChallengeData = data;
      _challengeStreamController.add(data);
    }
  }

  void notifyChallengeReceived(Map<String, dynamic> data) {
    debugPrint('OneAuth SDK: Emitting Notification/Verify Payload: $data');
    _latestChallengeData = data;
    _challengeStreamController.add(data);
  }

  void dispose() {
    _challengeStreamController.close();
  }
}
