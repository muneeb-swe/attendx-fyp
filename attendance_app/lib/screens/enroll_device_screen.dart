import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';

class EnrollDeviceScreen extends StatefulWidget {
  const EnrollDeviceScreen({super.key});

  @override
  State<EnrollDeviceScreen> createState() => _EnrollDeviceScreenState();
}

class _EnrollDeviceScreenState extends State<EnrollDeviceScreen> {
  bool _isLoading = false;
  bool _isSuccess = false;
  String _errorMessage = '';
  String _statusMessage = '';

  Future<void> _enrollDevice() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _statusMessage = 'Checking device...';
    });

    try {
      /// Allow re-enrollment — server handles hardware ID check

      setState(() {
        _statusMessage = 'Getting device info...';
      });

      // Step 2: Get device fingerprint
      String deviceFingerprint = 'unknown-device';
      try {
        deviceFingerprint = await CryptoService.getDeviceFingerprint();
      } catch (e) {
        // Use fallback on non-Android devices
        deviceFingerprint = 'web-test-device';
      }

      setState(() {
        _statusMessage = 'Generating security keys...';
      });

      setState(() {
        _statusMessage = 'Generating security keys...';
      });

      // Step 3: Generate real RSA key pair in Android Keystore
      final publicKey = await CryptoService.generateKeyPair();
      if (publicKey == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to generate keys';
        });
        return;
      }

      // Step 5: Send to server
      final result = await ApiService.enrollDevice(
        publicKey: publicKey,
        deviceFingerprint: deviceFingerprint,
      );

      if (result['status'] == 201) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
          _statusMessage = 'Device enrolled successfully!';
        });
      } else {
        final error = result['data'];
        String errorMsg = '';
        if (error is Map) {
          error.forEach((key, value) {
            if (value is List) {
              errorMsg += '${value[0]}\n';
            } else {
              errorMsg += '$value\n';
            }
          });
        }
        setState(() {
          _isLoading = false;
          _errorMessage = errorMsg.trim();
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connection error. Is the server running?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F2EB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0F)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Enroll Device',
          style: TextStyle(
            color: Color(0xFF0A0A0F),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Register Your Phone',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A0A0F),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This links your phone to your account. Only this phone can mark your attendance.',
                style: TextStyle(
                  color: Color(0xFF8A8A9A),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // Steps explanation
              _buildStep(
                number: '1',
                title: 'Device Identity',
                description: 'Your phone\'s unique ID is captured',
              ),
              _buildStep(
                number: '2',
                title: 'Security Keys',
                description:
                    'A cryptographic key pair is generated in your phone\'s secure hardware',
              ),
              _buildStep(
                number: '3',
                title: 'Server Registration',
                description:
                    'Your public key is sent to the server and linked to your account',
              ),
              _buildStep(
                number: '4',
                title: 'Ready',
                description:
                    'Only this phone can now mark your attendance',
              ),

              const SizedBox(height: 32),

              // Status message
              if (_statusMessage.isNotEmpty && _isLoading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: const Color(0xFF00C896)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Color(0xFF00C896),
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Color(0xFF00C896),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              // Success message
              if (_isSuccess)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: const Color(0xFF00C896)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Color(0xFF00C896)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Device enrolled successfully! You can now mark attendance.',
                          style: TextStyle(
                            color: Color(0xFF00C896),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Error message
              if (_errorMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFFF5C38).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: const Color(0xFFFF5C38)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFFF5C38), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Color(0xFFFF5C38),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              // Enroll button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading || _isSuccess
                      ? null
                      : _enrollDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A0A0F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  icon: _isSuccess
                      ? const Icon(Icons.check, size: 18)
                      : const Icon(Icons.phone_android, size: 18),
                  label: Text(
                    _isSuccess ? 'ENROLLED' : 'ENROLL THIS DEVICE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              if (_isSuccess) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(
                            context, '/student_home'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text(
                      'GO TO HOME',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF00C896)),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF00C896),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF0A0A0F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF8A8A9A),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}