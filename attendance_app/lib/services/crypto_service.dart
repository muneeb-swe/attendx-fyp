import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Thrown by generateKeyPair() and signData() when the platform reports a
/// specific, known reason for failure (no lock screen, no biometric
/// enrolled, user canceled, etc.), identified by [code]. Anything else
/// falls back to returning null, same as before.
class CryptoAuthException implements Exception {
  final String code;
  final String message;
  CryptoAuthException(this.code, this.message);
}

class CryptoService {
  static const MethodChannel _channel =
      MethodChannel('com.example.attendance_app/keystore');

  // Get device fingerprint
  static Future<String> getDeviceFingerprint() async {
    try {
      if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        final identifier = iosInfo.identifierForVendor;
        if (identifier == null || identifier.isEmpty) return 'unknown-device';
        return '${iosInfo.name}-${iosInfo.model}-$identifier';
      }

      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final androidId = await _channel.invokeMethod<String>('getAndroidId');
      if (androidId == null || androidId.isEmpty) return 'unknown-device';
      return '${androidInfo.brand}-${androidInfo.model}-$androidId';
    } catch (e) {
      return 'unknown-device';
    }
  }

  // Check if key exists in the platform's secure key store
  static Future<bool> hasKeys() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasKey');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Generate RSA key pair in the platform's secure key store
  // (Android Keystore or iOS Keychain). Returns public key as Base64 string.
  //
  // Throws CryptoAuthException with code 'NO_LOCK_SCREEN' if the device
  // has no secure lock screen set up at all. Any other platform failure
  // still returns null, same as before.
  static Future<String?> generateKeyPair() async {
    try {
      final publicKey =
          await _channel.invokeMethod<String>('generateKeyPair');
      return publicKey;
    } on PlatformException catch (e) {
      if (e.code == 'NO_LOCK_SCREEN') {
        throw CryptoAuthException(
          e.code,
          e.message ?? 'No secure lock screen set up',
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get existing public key
  static Future<String?> getPublicKey() async {
    try {
      final publicKey =
          await _channel.invokeMethod<String>('getPublicKey');
      return publicKey;
    } catch (e) {
      return null;
    }
  }

  // Sign data using the private key in the platform's secure key store.
  //
  // Throws CryptoAuthException with code 'NO_BIOMETRIC_ENROLLED' if the
  // device has a lock screen but no fingerprint/Face ID set up, or
  // 'NO_LOCK_SCREEN' if it has neither. Any other platform failure
  // (including a genuine user cancel) still returns null, same as before.
  static Future<String?> signData(String data) async {
    try {
      final signature = await _channel.invokeMethod<String>(
        'signData',
        {'data': data},
      );
      return signature;
    } on PlatformException catch (e) {
      if (e.code == 'NO_BIOMETRIC_ENROLLED' || e.code == 'NO_LOCK_SCREEN') {
        throw CryptoAuthException(
          e.code,
          e.message ?? 'Authentication not available on this device',
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Delete key (for re-enrollment)
  static Future<void> deleteKeys() async {
    try {
      await _channel.invokeMethod('deleteKey');
    } catch (e) {
      // silent fail
    }
  }

  // Save keys — not needed anymore
  // Keys live in the platform's secure key store now
  static Future<void> saveKeys({
    required String privateKey,
    required String publicKey,
  }) async {
    // No-op — the platform's secure key store handles this
  }
}