import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  String _name = '';
  String _employeeId = '';
  String _department = '';
  bool _isLoading = true;

  // Hardcoded classes for now
  // Later we'll fetch from API
  List<Map<String, dynamic>> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final result = await ApiService.getTeacherClasses();
      if (result['status'] == 200 && mounted) {
        setState(() {
          _classes = List<Map<String, dynamic>>.from(
              result['data']['classes']);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('name') ?? '';
      _employeeId = prefs.getString('employee_id') ?? '';
      _department = prefs.getString('department') ?? '';
    });
  }

  Future<void> _logout() async {
    await ApiService.deleteToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
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
                              style: TextStyle(color: Color(0xFF00C896)),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Teacher Portal',
                        style: TextStyle(
                          color: Color(0xFF8A8A9A),
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

              // Teacher info card
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
                      _employeeId.isNotEmpty
                          ? _employeeId
                          : 'Teacher',
                      style: const TextStyle(
                        color: Color(0xFF00C896),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _department.isNotEmpty
                          ? _department
                          : 'Department',
                      style: const TextStyle(
                        color: Color(0xFF8A8A9A),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Classes section
              const Text(
                'YOUR CLASSES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A8A9A),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),

              // Class list
              ..._classes.map((cls) => _buildClassCard(cls)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassCard(Map<String, dynamic> cls) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE0DDD5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cls['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF0A0A0F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cls['subject'],
                    style: const TextStyle(
                      color: Color(0xFF8A8A9A),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: const Color(0xFF00C896)),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: Color(0xFF00C896),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Take attendance button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () async{
                int? expectedCount;

                // Ask teacher for expected count
                await showDialog(
                  context: context,
                  builder: (context) {
                    final controller = TextEditingController();

                    return AlertDialog(
                      title: const Text('Start Attendance'),
                      content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Expected students',
                          hintText: 'e.g. 30',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Skip'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            if (controller.text.isNotEmpty) {
                              expectedCount = int.tryParse(controller.text);
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('Start'),
                        ),
                      ],
                    );
                  },
                );

                if (!mounted) return;

                Navigator.pushNamed(
                  context,
                  '/qr_display',
                  arguments: {
                    'class_info': cls,
                    'expected_count': expectedCount,
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A0A0F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              icon: const Icon(Icons.qr_code, size: 18),
              label: const Text(
                'TAKE ATTENDANCE',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}