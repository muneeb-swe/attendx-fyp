import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb


class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  String _name = '';
  String _rollNumber = '';
  String _department = '';
  String _deviceStatus = '';
  bool _isLoading = true;
  bool _keystoreKeyExists = false;
  bool _isDeviceMismatch = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _checkDeviceStatus();
  }


  Future<void> _checkKeystoreKey() async {
  final hasKey = await CryptoService.hasKeys();
  setState(() {
    _keystoreKeyExists = hasKey;
  });
}

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('name') ?? '';
      _rollNumber = prefs.getString('roll_number') ?? '';
      _department = prefs.getString('department') ?? '';
    });
  }

  Future<void> _checkDeviceStatus() async {
    try {
      // Get device fingerprint
      String deviceFingerprint = 'unknown-device';
      try {
        deviceFingerprint = await CryptoService.getDeviceFingerprint();
      } catch (e) {
        // Use fallback on non-Android devices
        deviceFingerprint = 'web-test-device';
      }
      final result = await ApiService.getDeviceStatus(deviceFingerprint: deviceFingerprint,);
      setState(() {
        _deviceStatus = result['data']['status'];
        _isDeviceMismatch = _deviceStatus == 'device mismatch';
        _isLoading = false;
        if (_deviceStatus == 'enrolled') {
          _checkKeystoreKey();
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await ApiService.deleteToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  bool get _isMobile {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android || 
         defaultTargetPlatform == TargetPlatform.iOS;
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00C896),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0A0A0F),
                                  letterSpacing: -0.5,
                                ),
                                children: [
                                  TextSpan(text: 'Attend'),
                                  TextSpan(
                                    text: 'X',
                                    style:
                                        TextStyle(color: Color(0xFF00C896)),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Student Portal',
                              style: TextStyle(
                                color: const Color(0xFF8A8A9A),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout,
                              color: Color(0xFF0A0A0F)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Student info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0F),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _rollNumber,
                            style: const TextStyle(
                              color: Color(0xFF00C896),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _department,
                            style: const TextStyle(
                              color: Color(0xFF8A8A9A),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Device enrollment warning
                    if (_deviceStatus == 'not enrolled')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFF5C38).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: const Color(0xFFFF5C38)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber,
                                color: Color(0xFFFF5C38)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Device Not Enrolled',
                                    style: TextStyle(
                                      color: Color(0xFFFF5C38),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'You must enroll your device before marking attendance.',
                                    style: TextStyle(
                                      color: Color(0xFFFF5C38),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () async {
                                          await Navigator.pushNamed(context, '/enroll_device');
                                          _checkDeviceStatus();
                                        },
                                        child: const Text(
                                          'Enroll Device →',                                  style: TextStyle(
                                        color: Color(0xFFFF5C38),
                                        fontWeight: FontWeight.w700,
                                        decoration:
                                            TextDecoration.underline,
                                          )
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Actions
                    const Text(
                      'QUICK ACTIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8A9A),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scan QR button
                    if (_isMobile)
                    _buildActionCard(
                      icon: Icons.qr_code_scanner,
                      title: 'Scan QR Code',
                      subtitle: 'Mark your attendance',
                      color: const Color(0xFF00C896),
                      onTap: _deviceStatus == 'enrolled'
                          ? () =>
                              Navigator.pushNamed(context, '/scan_qr')
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Please enroll your device first'),
                                  backgroundColor: Color(0xFFFF5C38),
                                ),
                              );
                            },
                    ),

                    const SizedBox(height: 12),

                    // Attendance history button
                    _buildActionCard(
                      icon: Icons.history,
                      title: 'Attendance History',
                      subtitle: 'View your past attendance',
                      color: const Color(0xFF5B8FF9),
                      onTap: () => Navigator.pushNamed(
                          context, '/attendance_history'),
                    ),

                    const SizedBox(height: 12),

                    // Enroll device button
                    _buildActionCard(
                      icon: Icons.phone_android,
                      title: _isDeviceMismatch
                        ? 'Device Mismatch'
                        : (!_keystoreKeyExists && _deviceStatus == 'enrolled')
                          ? 'Re-enroll Device'
                          : _deviceStatus == 'enrolled'
                            ? 'Device Enrolled ✓'
                            : 'Enroll Device',
                    subtitle: _isDeviceMismatch
                        ? 'Contact admin to reset your device'
                        : (!_keystoreKeyExists && _deviceStatus == 'enrolled')
                          ? 'Reinstalled app? Re-register your device'
                          : _deviceStatus == 'enrolled'
                            ? 'Your device is registered'
                            : 'Register your phone for attendance',
                    color: _isDeviceMismatch
                        ? const Color(0xFFFF5C38)
                        : _deviceStatus == 'enrolled'
                          ? const Color(0xFF8A8A9A)
                          : const Color(0xFFFF5C38),
                      onTap: _isDeviceMismatch
                        ? null
                        : (!_keystoreKeyExists && _deviceStatus == 'enrolled')
                          ? () async {
                              await Navigator.pushNamed(context, '/enroll_device');
                              _checkDeviceStatus();
                            }
                          : _deviceStatus == 'enrolled'
                            ? null
                            : () async {
                                await Navigator.pushNamed(context, '/enroll_device');
                                _checkDeviceStatus();
                              },
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFE0DDD5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF0A0A0F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8A8A9A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Color(0xFF8A8A9A)),
            ],
          ),
        ),
      )
    );
  }
}