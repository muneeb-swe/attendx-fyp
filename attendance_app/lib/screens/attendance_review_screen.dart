import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AttendanceReviewScreen extends StatefulWidget {
  const AttendanceReviewScreen({super.key});

  @override
  State<AttendanceReviewScreen> createState() =>
      _AttendanceReviewScreenState();
}

class _AttendanceReviewScreenState extends State<AttendanceReviewScreen> {
  Map<String, dynamic>? _args;
  int _sessionId = 0;
  Map<String, dynamic>? _classInfo;
  List<dynamic> _students = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _errorMessage = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (_args != null && _sessionId == 0) {
      _sessionId = _args!['session_id'];
      _classInfo = _args!['class_info'];
      _loadAttendance();
    }
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await ApiService.getSessionAttendance(_sessionId);
      if (result['status'] == 200 && mounted) {
        setState(() {
          _students = result['data']['students'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load attendance';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleStatus(int index) async {
    final student = _students[index];
    final recordId = student['record_id'];
    final currentStatus = student['status'];
    final newStatus = currentStatus == 'present' ? 'absent' : 'present';

    try {
      final result = await ApiService.editAttendance(
        recordId: recordId,
        status: newStatus,
      );

      if (result['status'] == 200 && mounted) {
        setState(() {
          _students[index]['status'] = newStatus;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update attendance')),
        );
      }
    }
  }

  Future<void> _submitAttendance() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Attendance?'),
        content: const Text(
            'Once submitted attendance cannot be changed. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
            ),
            child: const Text('Submit',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await ApiService.submitAttendance(_sessionId);
      if (result['status'] == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance submitted successfully!'),
            backgroundColor: Color(0xFF00C896),
          ),
        );
        Navigator.pushReplacementNamed(context, '/teacher_home');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit attendance')),
        );
      }
    }
  }

  int get _totalPresent =>
      _students.where((s) => s['status'] == 'present').length;
  int get _totalAbsent =>
      _students.where((s) => s['status'] == 'absent').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F2EB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0F)),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, '/teacher_home'),
        ),
        title: Text(
          _classInfo?['name'] ?? 'Review Attendance',
          style: const TextStyle(
            color: Color(0xFF0A0A0F),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00C896),
              ),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage,
                          style: const TextStyle(
                              color: Color(0xFFFF5C38))),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadAttendance,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Stats bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStat(
                              'PRESENT',
                              '$_totalPresent',
                              const Color(0xFF00C896),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: const Color(0xFFE0DDD5),
                          ),
                          Expanded(
                            child: _buildStat(
                              'ABSENT',
                              '$_totalAbsent',
                              const Color(0xFFFF5C38),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: const Color(0xFFE0DDD5),
                          ),
                          Expanded(
                            child: _buildStat(
                              'TOTAL',
                              '${_students.length}',
                              const Color(0xFF0A0A0F),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Instructions
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: const Color(0xFF0A0A0F).withOpacity(0.05),
                      child: const Text(
                        'Tap any student to toggle present/absent',
                        style: TextStyle(
                          color: Color(0xFF8A8A9A),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // Student list
                    Expanded(
                      child: ListView.builder(
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final isPresent =
                              student['status'] == 'present';

                          return GestureDetector(
                            onTap: () => _toggleStatus(index),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isPresent
                                      ? const Color(0xFF00C896)
                                          .withOpacity(0.3)
                                      : const Color(0xFFE0DDD5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Status icon
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isPresent
                                          ? const Color(0xFF00C896)
                                              .withOpacity(0.1)
                                          : const Color(0xFFFF5C38)
                                              .withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      isPresent
                                          ? Icons.check
                                          : Icons.close,
                                      color: isPresent
                                          ? const Color(0xFF00C896)
                                          : const Color(0xFFFF5C38),
                                      size: 18,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  // Student info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: Color(0xFF0A0A0F),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          student['roll_number'],
                                          style: const TextStyle(
                                            color: Color(0xFF8A8A9A),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Status badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isPresent
                                          ? const Color(0xFF00C896)
                                              .withOpacity(0.1)
                                          : const Color(0xFFFF5C38)
                                              .withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(2),
                                      border: Border.all(
                                        color: isPresent
                                            ? const Color(0xFF00C896)
                                            : const Color(0xFFFF5C38),
                                      ),
                                    ),
                                    child: Text(
                                      isPresent ? 'PRESENT' : 'ABSENT',
                                      style: TextStyle(
                                        color: isPresent
                                            ? const Color(0xFF00C896)
                                            : const Color(0xFFFF5C38),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Submit button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed:
                              _isSubmitting ? null : _submitAttendance,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C896),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle, size: 18),
                          label: Text(
                            _isSubmitting
                                ? 'SUBMITTING...'
                                : 'SUBMIT ATTENDANCE',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF8A8A9A),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}