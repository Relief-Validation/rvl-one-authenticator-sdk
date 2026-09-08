import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Unified manager for persistent secure IDs stored in FlutterSecureStorage.
class OneAuthSecureIdManager {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Gets an existing ID by [key] from secure storage or generates and persists a new UUID v4.
  static Future<String> getOrCreateId(
    String key, {
    String prefix = '',
    bool isAuthId = false,
  }) async {
    String? id = await _storage.read(key: key);
    if (id == null || id.isEmpty) {
      if (isAuthId) {
        final suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
        id = '$prefix$suffix';
      } else {
        id = '$prefix${const Uuid().v4()}';
      }
      await _storage.write(key: key, value: id);
    }
    return id;
  }

  /// Convenience getter for persistent device UUID ('device_uuid').
  static Future<String> getOrCreateDeviceUuid() async {
    return getOrCreateId('device_uuid');
  }

  /// Convenience getter for persistent app instance ID ('app_instance_id').
  static Future<String> getOrCreateAppInstanceId() async {
    return getOrCreateId('app_instance_id', prefix: 'instance-');
  }
}
