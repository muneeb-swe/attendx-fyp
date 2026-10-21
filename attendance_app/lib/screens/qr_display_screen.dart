import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  bool _isFullScreen = false;

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
      final result = await ApiService.generateQR(_classInfo!['class_info']['id'], expectedCount: _classInfo!['expected_count'],);
      print('QR RESULT: $result');
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
        final data = result['data'];
        setState(() {
          _errorMessage = (data is Map && data['error'] is String)
              ? data['error']
              : 'Failed to generate QR';
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
    final WebSocketChannel channel;
    try {
      channel = await ApiService.connectAuthenticatedSocket(
        '/ws/attendance/session/$_sessionId/',
      );
    } catch (e) {
      // Could not connect: retry shortly, same as a dropped connection.
      if (mounted && _sessionStarted) {
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      }
      return;
    }
    if (!mounted) {
      channel.sink.close();
      return;
    }
    _wsChannel = channel;
    _wsChannel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['type'] == 'attendance_update' && mounted) {
          final totalPresent = data['total_present'] ?? 0;
          final autoStopped = data['auto_stopped'] ?? false;
          setState(() {
            _totalPresent = totalPresent;
          });

          // Backend automatically stopped the session
          if (autoStopped) {
            _stopSession(automatic: true);
          }
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
    WakelockPlus.enable();
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


  Future<void> _stopSession({bool automatic = false}) async {
    if (_isFullScreen) _exitFullScreen();
    if (!automatic) {
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
                style: TextStyle(color: Colors.white)
                ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    }

    _countdownTimer?.cancel();
    setState(() {
      _isLoading = true;
      _qrImage = '';
    });

    try {
      // Only manually stopped sessions need the API call.
      if (!automatic) {
        final result = await ApiService.stopSession(_sessionId);
        if (result['status'] != 200) {
          throw Exception('Failed to stop session');
        }
      }

      if (mounted) {
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
          const SnackBar(
            content: Text('Error stopping session')
          ),
        );
      }
    }
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _isFullScreen = true);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    if (mounted) setState(() => _isFullScreen = false);
  }

  // Full-screen view: the QR code fills the full height of the screen (or the
  // full width on a portrait phone), never larger than the screen. The count
  // and countdown go in the spare space beside or above/below the code, so
  // nothing overlaps it. Tap anywhere (or press back) to leave.
  Widget _buildFullScreen() {
    final presentText = _classInfo?['expected_count'] != null
        ? '$_totalPresent / ${_classInfo!['expected_count']} Present'
        : '$_totalPresent Present';

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _exitFullScreen,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape = constraints.maxWidth >= constraints.maxHeight;
              final side =
                  landscape ? constraints.maxHeight : constraints.maxWidth;
              final spare = landscape
                  ? (constraints.maxWidth - side) / 2
                  : (constraints.maxHeight - side) / 2;
              // Only show the side panels when there is room for them.
              final showPanels = spare >= 110;

              final qr = SizedBox(
                width: side,
                height: side,
                child: Image.memory(
                  base64Decode(
                    _qrImage.replaceFirst('data:image/png;base64,', ''),
                  ),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  gaplessPlayback: true,
                ),
              );

              Widget panel(List<Widget> children) => Expanded(
                    child: showPanels
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: children,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  );

              final countPanel = panel([
                Text(
                  presentText,
                  style: const TextStyle(
                    color: Color(0xFF0A0A0F),
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]);

              final timerPanel = panel([
                Text(
                  '$_countdown s',
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'until refresh',
                  style: TextStyle(color: Color(0xFF8A8A9A), fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tap to exit',
                  style: TextStyle(color: Color(0xFF8A8A9A), fontSize: 16),
                ),
              ]);

              return landscape
                  ? Row(children: [countPanel, qr, timerPanel])
                  : Column(children: [countPanel, qr, timerPanel]);
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _countdownTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

Future<bool> _onWillPop() async {
    if (_isFullScreen) {
    _exitFullScreen();
    return false;
  }
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
    if (_isFullScreen && _qrImage.isNotEmpty) {
      return WillPopScope(
        onWillPop: _onWillPop,
        child: _buildFullScreen(),
      );
    }
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
            if (_sessionStarted && _qrImage.isNotEmpty)
            IconButton(
              tooltip: 'Full screen',
              icon: const Icon(Icons.fullscreen, color: Color(0xFF0A0A0F)),
              onPressed: _enterFullScreen,
            ),
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
                                child: _qrImage.isNotEmpty && !_isRefreshing
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