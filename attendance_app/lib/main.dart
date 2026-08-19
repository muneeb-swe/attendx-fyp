import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_home.dart';
import 'screens/teacher_home.dart';
import 'screens/qr_display_screen.dart';
import 'screens/attendance_review_screen.dart';
import 'screens/scan_qr_screen.dart';
import 'screens/enroll_device_screen.dart';
import 'screens/attendance_history_screen.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C896),
        ),
        useMaterial3: true,
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/student_home': (context) => const StudentHomeScreen(),
        '/teacher_home': (context) => const TeacherHomeScreen(),
        '/qr_display': (context) => const QRDisplayScreen(),
        '/attendance_review': (context) => const AttendanceReviewScreen(),
        '/scan_qr': (context) => const ScanQRScreen(),
        '/enroll_device': (context) => const EnrollDeviceScreen(),
        '/attendance_history': (context) => const AttendanceHistoryScreen(),
      },
    );
  }
}