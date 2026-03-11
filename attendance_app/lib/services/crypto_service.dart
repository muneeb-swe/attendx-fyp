import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

class CryptoService {
  static const MethodChannel _channel =
      MethodChannel('com.example.attendance_app/keystore');

  // Get device fingerprint
  static Future<String> getDeviceFingerprint() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return '${androidInfo.brand}-${androidInfo.model}-${androidInfo.id}';
    } catch (e) {
      return 'unknown-device';
    }
  }

  // Check if key exists in Android Keystore
  static Future<bool> hasKeys() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasKey');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Generate RSA key pair in Android Keystore
  // Returns public key as Base64 string
  static Future<String?> generateKeyPair() async {
    try {
      final publicKey =
          await _channel.invokeMethod<String>('generateKeyPair');
      return publicKey;
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

  // Sign data using private key in Android Keystore
  static Future<String?> signData(String data) async {
    try {
      final signature = await _channel.invokeMethod<String>(
        'signData',
        {'data': data},
      );
      return signature;
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
  // Keys live in Android Keystore now
  static Future<void> saveKeys({
    required String privateKey,
    required String publicKey,
  }) async {
    // No-op — Android Keystore handles this
  }
}