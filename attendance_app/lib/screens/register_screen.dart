import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _rollNumberController = TextEditingController();
  final _departmentController = TextEditingController();
  final _batchController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String _errorMessage = '';

  Future<void> _register() async {
    // Validate all fields
    if (_usernameController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _rollNumberController.text.isEmpty ||
        _departmentController.text.isEmpty ||
        _batchController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill all required fields';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await ApiService.register(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        rollNumber: _rollNumberController.text.trim(),
        department: _departmentController.text.trim(),
        batch: _batchController.text.trim(),
      );

      if (result['status'] == 201) {
        final data = result['data'];

        // Save token and user info
        await ApiService.saveToken(data['access_token']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', data['role']);
        await prefs.setString('name', data['name']);
        await prefs.setString('username', data['username']);
        await prefs.setString('roll_number', data['roll_number'] ?? '');

        if (!mounted) return;

        // Go to student home after register
        Navigator.pushReplacementNamed(context, '/student_home');
      } else {
        // Show error from server
        final errors = result['data'];
        String errorMsg = '';
        errors.forEach((key, value) {
          if (value is List) {
            errorMsg += '${value[0]}\n';
          } else {
            errorMsg += '$value\n';
          }
        });
        setState(() {
          _errorMessage = errorMsg.trim();
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Is the server running?';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    bool showToggle = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8A8A9A),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: showToggle ? _obscurePassword : obscure,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF8A8A9A)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFFE0DDD5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFFE0DDD5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFF00C896)),
            ),
            suffixIcon: showToggle
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: const Color(0xFF8A8A9A),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0A0A0F),
                    letterSpacing: -1,
                  ),
                  children: [
                    TextSpan(text: 'Create\nAccount'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Register as a student',
                style: TextStyle(
                  color: Color(0xFF8A8A9A),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Fields
              _buildField(
                label: 'FIRST NAME',
                controller: _firstNameController,
                hint: 'Enter your first name',
              ),
              _buildField(
                label: 'LAST NAME',
                controller: _lastNameController,
                hint: 'Enter your last name',
              ),
              _buildField(
                label: 'ROLL NUMBER',
                controller: _rollNumberController,
                hint: 'e.g. S23-0259',
              ),
              _buildField(
                label: 'USERNAME',
                controller: _usernameController,
                hint: 'Choose a username',
              ),
              _buildField(
                label: 'PASSWORD',
                controller: _passwordController,
                hint: 'Choose a password',
                showToggle: true,
              ),
              _buildField(
                label: 'DEPARTMENT',
                controller: _departmentController,
                hint: 'e.g. CS, SE, IT',
              ),
              _buildField(
                label: 'BATCH',
                controller: _batchController,
                hint: 'e.g. 2023',
              ),
              _buildField(
                label: 'PHONE (optional)',
                controller: _phoneController,
                hint: 'e.g. 03001234567',
                keyboard: TextInputType.phone,
              ),

              // Error message
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5C38).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFF5C38)),
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

              // Register button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A0A0F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'CREATE ACCOUNT',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Login link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(color: Color(0xFF8A8A9A)),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(
                          color: Color(0xFF00C896),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}