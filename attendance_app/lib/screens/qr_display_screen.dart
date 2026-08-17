import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class QRDisplayScreen extends StatefulWidget {
  const QRDisplayScreen({super.key});

  @override
  State<QRDisplayScreen> createState() => _QRDisplayScreenState();
}

class _QRDisplayScreenState extends State<QRDisplayScreen> {
  Map<String, dynamic>? _classInfo;
  String _qrImage = '';
  int _sessionId = 0;
  int _countdown = 5;
  bool _isLoading = true;
  bool _sessionStarted = false;
  bool _isRefreshing = false;
  String _errorMessage = '';
  Timer? _countdownTimer;
  int _totalPresent = 0;
  WebSocketChannel? _wsChannel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newClassInfo =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (newClassInfo != null) {
      final isSameClass = _classInfo != null &&
          newClassInfo['id'] == _classInfo!['id'];
      if (!isSameClass || !_sessionStarted) {
        _classInfo = newClassInfo;
        _countdownTimer?.cancel();
        _sessionStarted = false;
        _startSession();
      }
    }
  }

  Future<void> _startSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await ApiService.generateQR(_classInfo!['id'], expectedCount: _classInfo!['expected_count'],);
      if (result['status'] == 201) {
        final data = result['data'];
        _sessionId = data['session_id'];
        _qrImage = data['qr_image'];
        _sessionStarted = true;
        _countdown = 5;
        setState(() {
          _isLoading = false;
        });
        _startTimers();
      } else {
        setState(() {
          _errorMessage = 'Failed to generate QR';
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

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_isRefreshing) return; // pause during refresh
      if (_countdown <= 0) return; // prevent going negative
      setState(() {
        _countdown--;
      });
      if (_countdown <= 0) {
        _refreshQR();
      }
    });
  }

  void _connectWebSocket() async {
    final token = await ApiService.getToken();
    final wsUrl = 'wss://attendx-fyp-production.up.railway.app/ws/attendance/session/$_sessionId/?token=$token';
    
    _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _wsChannel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['type'] == 'attendance_update' && mounted) {
          setState(() {
            _totalPresent = data['total_present'];
          });
        }
      },
      onError: (error) {
        // silently fail — not critical
      },
      onDone: () {
        // reconnect if disconnected
        if (mounted && _sessionStarted) {
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        }
      },
    );
  }

  void _startTimers() {
    _startCountdownTimer();
    _connectWebSocket();
  }

  Future<void> _refreshQR() async {
    if (_isRefreshing) return; // prevent double refresh
    _isRefreshing = true;
    _countdownTimer?.cancel(); // stop timer during network call

    try {
      final result = await ApiService.refreshQR(_sessionId);
      if (result['status'] == 200 && mounted) {
        _qrImage = result['data']['qr_image'];
        _countdown = 5;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        _countdown = 5;
        setState(() {});
      }
    }

    _isRefreshing = false;
    if (mounted) {
      _startCountdownTimer(); // restart timer after refresh done
    }
  }


  Future<void> _stopSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Attendance?'),
        content: const Text(
            'This will end the session and mark absent students.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C38),
            ),
            child: const Text('Stop',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _countdownTimer?.cancel();
    setState(() {
      _isLoading = true;
      _qrImage = '';
    });

    try {
      final result = await ApiService.stopSession(_sessionId);
      if (result['status'] == 200 && mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/attendance_review',
          arguments: {
            'session_id': _sessionId,
            'class_info': _classInfo
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error stopping session')),
        );
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

Future<bool> _onWillPop() async {
  if (!_sessionStarted) return true;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard Session?'),
      content: const Text(
          'Going back will discard this session and all attendance records will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Stay'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5C38),
          ),
          child: const Text('Discard',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (confirm == true) {
    _countdownTimer?.cancel();
    await ApiService.discardSession(_sessionId);
    return true;
  }
  return false;
}

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
    onWillPop: _onWillPop,
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F2EB),
        elevation: 0,
        leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0F)),
        onPressed: () async {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) Navigator.pop(context);
        },
      ),
        title: Text(
          _classInfo?['name'] ?? 'Attendance',
          style: const TextStyle(
            color: Color(0xFF0A0A0F),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_sessionStarted)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFF00C896)),
                  ),
                  child: Text(
                    _classInfo?['expected_count'] != null
                        ? '$_totalPresent / ${_classInfo!['expected_count']} Present'
                        : '$_totalPresent Present',
                    style: const TextStyle(
                      color: Color(0xFF00C896),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
                          style:
                              const TextStyle(color: Color(0xFFFF5C38))),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _startSession,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              _classInfo?['subject'] ?? '',
                              style: const TextStyle(
                                color: Color(0xFF8A8A9A),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),

                            RepaintBoundary(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0A0F),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: _qrImage.isNotEmpty
                                    ? Image.memory(
                                        base64Decode(
                                          _qrImage.replaceFirst(
                                              'data:image/png;base64,',
                                              ''),
                                        ),
                                        width: 220,
                                        height: 220,
                                        gaplessPlayback: true,
                                      )
                                    : const SizedBox(
                                        width: 220,
                                        height: 220,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF00C896),
                                          ),
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isRefreshing
                                      ? 'Refreshing QR...'
                                      : 'Refreshing in ',
                                  style: const TextStyle(
                                    color: Color(0xFF8A8A9A),
                                    fontSize: 14,
                                  ),
                                ),
                                if (!_isRefreshing)
                                  Text(
                                    '$_countdown seconds',
                                    style: TextStyle(
                                      color: _countdown <= 5
                                          ? const Color(0xFFFF5C38)
                                          : const Color(0xFF00C896),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            LinearProgressIndicator(
                              value: _isRefreshing ? null : _countdown / 5,
                              backgroundColor: const Color(0xFFE0DDD5),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _countdown <= 5
                                    ? const Color(0xFFFF5C38)
                                    : const Color(0xFF00C896),
                              ),
                            ),

                            const SizedBox(height: 24),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFFE0DDD5)),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Color(0xFF8A8A9A)),
                                  SizedBox(height: 8),
                                  Text(
                                    'Ask students to open the app and scan this QR code. The code refreshes every 5 seconds automatically.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF8A8A9A),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _stopSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5C38),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          icon: const Icon(Icons.stop_circle, size: 18),
                          label: const Text(
                            'STOP & REVIEW ATTENDANCE',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    )
    );
  }
}