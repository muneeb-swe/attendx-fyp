import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // Change this to your Django server IP
  static const String baseUrl = 'http://192.168.1.13:8000/api';
  static const FlutterSecureStorage storage = FlutterSecureStorage();

  // Save token after login
  static Future<void> saveToken(String token) async {
    await storage.write(key: 'access_token', value: token);
  }

  // Get saved token
  static Future<String?> getToken() async {
    return await storage.read(key: 'access_token');
  }

  // Delete token on logout
  static Future<void> deleteToken() async {
    await storage.delete(key: 'access_token');
  }

  // Headers with token
  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
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

  // REGISTER
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String rollNumber,
    required String department,
    required String batch,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'roll_number': rollNumber,
        'department': department,
        'batch': batch,
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
  static Future<Map<String, dynamic>> generateQR(int classId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/generate-qr/'),
      headers: headers,
      body: jsonEncode({'class_id': classId}),
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

  // MARK ATTENDANCE (student)
  static Future<Map<String, dynamic>> markAttendance({
    required int sessionId,
    required String qrToken,
    required String signature,
  }) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/mark/'),
      headers: headers,
      body: jsonEncode({
        'session_id': sessionId,
        'qr_token': qrToken,
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
  static Future<Map<String, dynamic>> getDeviceStatus() async {
    final headers = await getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/auth/device/status/'),
      headers: headers,
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
}