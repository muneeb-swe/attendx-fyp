import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends State<AttendanceHistoryScreen> {
  List<dynamic> _records = [];
  bool _isLoading = true;
  String _errorMessage = '';
  WebSocketChannel? _wsChannel;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _connectWebSocket();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await ApiService.getAttendanceHistory();
      if (result['status'] == 200 && mounted) {
        setState(() {
          _records = result['data']['records'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load history';
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

  void _connectWebSocket() async {
    final token = await ApiService.getToken();
    final wsUrl = 'wss://attendx-backend.onrender.com/ws/attendance/student/history/?token=$token';
    _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _wsChannel!.stream.listen(
      (message) {

        final data = jsonDecode(message);
        if (data['type'] == 'history_update' && mounted) {
          _loadHistory();
        }
      },
    );
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalPresent = _records.where((r) => (r['status'] as String).contains('present')).length;
    final totalAbsent = _records.where((r) => (r['status'] as String).contains('absent')).length;
    final percentage = _records.isEmpty
        ? 0.0
        : (totalPresent / _records.length) * 100;

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
          'Attendance History',
          style: TextStyle(
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
                        onPressed: _loadHistory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0F),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                            children: [
                              _buildStat(
                                'PRESENT',
                                '$totalPresent',
                                const Color(0xFF00C896),
                              ),
                              _buildStat(
                                'ABSENT',
                                '$totalAbsent',
                                const Color(0xFFFF5C38),
                              ),
                              _buildStat(
                                'TOTAL',
                                '${_records.length}',
                                Colors.white,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Percentage bar
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Attendance Rate',
                                    style: TextStyle(
                                      color: Color(0xFF8A8A9A),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${percentage.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: percentage >= 75
                                          ? const Color(0xFF00C896)
                                          : const Color(0xFFFF5C38),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: percentage / 100,
                                backgroundColor:
                                    Colors.white.withOpacity(0.1),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                  percentage >= 75
                                      ? const Color(0xFF00C896)
                                      : const Color(0xFFFF5C38),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                percentage >= 75
                                    ? '✓ Attendance requirement met'
                                    : '⚠ Below 75% requirement',
                                style: TextStyle(
                                  color: percentage >= 75
                                      ? const Color(0xFF00C896)
                                      : const Color(0xFFFF5C38),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Records list
                    Expanded(
                      child: _records.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 64,
                                    color: Color(0xFF8A8A9A),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No attendance records yet',
                                    style: TextStyle(
                                      color: Color(0xFF8A8A9A),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                            onRefresh: _loadHistory,
                            color: const Color(0xFF00C896),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              itemCount: _records.length,
                              itemBuilder: (context, index) {
                                final record = _records[index];
                                final status = record['status'] as String;
                                final isPending = status == 'pending';
                                final isPresent = status == 'present' || status == 'present (modified)';

                                return Container(
                                  margin: const EdgeInsets.only(
                                      bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isPending
                                    ? const Color(0xFFFFAA00).withOpacity(0.1)
                                    : isPresent
                                      ? const Color(0xFF00C896).withOpacity(0.1)
                                      : const Color(0xFFFF5C38).withOpacity(0.1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Status icon
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: isPending
                                              ? const Color(0xFFFFAA00).withOpacity(0.1)
                                              : isPresent
                                                ? const Color(0xFF00C896).withOpacity(0.1)
                                                : const Color(0xFFFF5C38).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(
                                          isPending ? Icons.hourglass_empty : isPresent ? Icons.check : Icons.close,
                                          color: isPending
                                              ? const Color(0xFFFFAA00)
                                              : isPresent
                                                ? const Color(0xFF00C896)
                                                : const Color(0xFFFF5C38),
                                          size: 18,
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      // Class info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              record['class_name'] ??
                                                  'Class',
                                              style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w600,
                                                fontSize: 14,
                                                color:
                                                    Color(0xFF0A0A0F),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              record['subject'] ?? '',
                                              style: const TextStyle(
                                                color:
                                                    Color(0xFF8A8A9A),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              record['timestamp'] ??
                                                  '',
                                              style: const TextStyle(
                                                color:
                                                    Color(0xFF8A8A9A),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Status badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        width: 90,
                                        decoration: BoxDecoration(
                                          color: isPending
                                              ? const Color(0xFFFFAA00).withOpacity(0.1)
                                              : isPresent
                                                ? const Color(0xFF00C896).withOpacity(0.1)
                                                : const Color(0xFFFF5C38).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(2),
                                          border: Border.all(
                                            color: isPending
                                                ? const Color(0xFFFFAA00)
                                                : isPresent
                                                  ? const Color(0xFF00C896)
                                                  : const Color(0xFFFF5C38),
                                          ),
                                        ),
                                        child: Text(
                                          isPending
                                              ? 'PENDING'
                                              : status.contains('modified')
                                                ? status.toUpperCase()
                                                : isPresent ? 'PRESENT' : 'ABSENT',
                                          maxLines: 2,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isPending
                                                ? const Color(0xFFFFAA00)
                                                : isPresent
                                                  ? const Color(0xFF00C896)
                                                  : const Color(0xFFFF5C38),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
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