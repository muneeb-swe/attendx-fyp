import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // Change this to your Django server IP
  //static const String baseUrl = 'http://MuneebOfficial-52165.portmap.host:52165/api';
  //static const String baseUrl = 'http://localhost:8000/api';
  static const String baseUrl = 'https://attendx-fyp-production.up.railway.app/api';
  static const FlutterSecureStorage storage = FlutterSecureStorage();

  // Save token after login
  static Future<void> saveToken(String token) async {
    await storage.write(key: 'access_token', value: token);
  }

  // Get saved token
  static Future<String?> getToken() async {
    return await storage.read(key: 'access_token');
  }

  // Delete both tokens on logout. The refresh token must go too,
  // otherwise a logged-out app could silently sign itself back in.
  static Future<void> deleteToken() async {
    await storage.delete(key: 'access_token');
    await storage.delete(key: 'refresh_token');
  }

  // True if the JWT has expired, or will within [skewSeconds].
  static bool _isExpiredOrExpiring(String token, {int skewSeconds = 30}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final exp = jsonDecode(payload)['exp'];
      if (exp is! int) return true;
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSeconds >= exp - skewSeconds;
    } catch (e) {
      return true;
    }
  }

  // Returns an access token that is valid right now, refreshing it first
  // if it has expired. Returns whatever is stored if the refresh fails,
  // so the server's 401 decides what happens next.
  static Future<String?> getValidToken() async {
    final token = await getToken();
    if (token != null && !_isExpiredOrExpiring(token)) return token;

    final refreshed = await _refreshToken();
    if (refreshed) return await getToken();
    return token;
  }

  // Headers with token
  static Future<Map<String, String>> getHeaders() async {
    final token = await getValidToken();
    if (token == null) return {'Content-Type': 'application/json'};

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<bool> _refreshToken() async {
    final refreshToken = await storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await saveToken(data['access']);
        return true;
      }
    } catch (e) {
      // Network error: treat as "could not refresh".
    }
    return false;
  }

  // LOGIN
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // ENROLL DEVICE
  static Future<Map<String, dynamic>> enrollDevice({
    required String publicKey,
    required String deviceFingerprint,
  }) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/auth/device/enroll/'),
      headers: headers,
      body: jsonEncode({
        'public_key': publicKey,
        'device_fingerprint': deviceFingerprint,
      }),
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // GENERATE QR (teacher)
  static Future<Map<String, dynamic>> generateQR(int classId, {int? expectedCount,}) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/generate-qr/'),
      headers: headers,
      body: jsonEncode({
        'class_id': classId,
        if (expectedCount != null)
          'expected_count': expectedCount,
        }),
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // REFRESH QR (teacher)
  static Future<Map<String, dynamic>> refreshQR(int sessionId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/session/$sessionId/refresh-qr/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // STOP SESSION (teacher)
  static Future<Map<String, dynamic>> stopSession(int sessionId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/session/$sessionId/stop/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // GET SESSION ATTENDANCE (teacher)
  static Future<Map<String, dynamic>> getSessionAttendance(
      int sessionId) async {
    final headers = await getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/session/$sessionId/attendance/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  static Future<Map<String, dynamic>> registerScan({
    required int sessionId,
    required String qrToken,
  }) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/register-scan/'),
      headers: headers,
      body: jsonEncode({
        'session_id': sessionId,
        'qr_token': qrToken,
      }),
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // MARK ATTENDANCE (student)
  static Future<Map<String, dynamic>> markAttendance({
  required String scanToken,
  required String signature,
}) async {
  final headers = await getHeaders();
  final response = await http.post(
    Uri.parse('$baseUrl/attendance/mark/'),
    headers: headers,
    body: jsonEncode({
      'scan_token': scanToken,
      'signature': signature,
    }),
  );

  return {
    'status': response.statusCode,
    'data': jsonDecode(response.body),
  };
}

  // SUBMIT ATTENDANCE (teacher)
  static Future<Map<String, dynamic>> submitAttendance(
      int sessionId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/session/$sessionId/submit/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // EDIT ATTENDANCE (teacher)
  static Future<Map<String, dynamic>> editAttendance({
    required int recordId,
    required String status,
  }) async {
    final headers = await getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/attendance/record/$recordId/edit/'),
      headers: headers,
      body: jsonEncode({'status': status}),
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // GET DEVICE STATUS
  static Future<Map<String, dynamic>> getDeviceStatus({
    required String deviceFingerprint,
    }) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/auth/device/status/'),
      headers: headers,
      body: jsonEncode({'device_fingerprint': deviceFingerprint}),
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // GET TEACHER CLASSES
  static Future<Map<String, dynamic>> getTeacherClasses() async {
    final headers = await getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/teacher/classes/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // GET ATTENDANCE HISTORY (student)
  static Future<Map<String, dynamic>> getAttendanceHistory() async {
    final headers = await getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/student/history/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  static Future<Map<String, dynamic>> discardSession(int sessionId) async {
    final headers = await getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/attendance/session/$sessionId/discard/'),
      headers: headers,
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  static Future<bool> verifyToken() async {
    try {
      final headers = await getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/verify/'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}