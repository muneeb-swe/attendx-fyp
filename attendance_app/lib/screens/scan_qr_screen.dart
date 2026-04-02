import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';

class ScanQRScreen extends StatefulWidget {
  const ScanQRScreen({super.key});

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isProcessing = false;
  bool _scanComplete = false;
  String _statusMessage = 'Point camera at QR code';
  String _statusSubMessage = '';
  bool _isSuccess = false;
  bool _isError = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onQRDetected(BarcodeCapture capture) async {
    // Prevent multiple scans
    if (_isProcessing || _scanComplete) return;

    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    final qrData = barcode.rawValue!;
    final scanTimestamp = DateTime.now().millisecondsSinceEpoch;

    // QR format: session_id:qr_token
    final parts = qrData.split(':');
    if (parts.length < 2) {
      _showError('Invalid QR code format');
      return;
    }

    final sessionId = int.tryParse(parts[0]);
    final qrToken = parts.sublist(1).join(':');

    if (sessionId == null) {
      _showError('Invalid QR code');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'QR Detected!';
      _statusSubMessage = 'Verifying biometric...';
    });

    // Stop scanner
    _scannerController.stop();

    setState(() {
    _statusMessage = 'Authenticating...';
    _statusSubMessage = 'Place your finger on the sensor';
  });

    // Biometric + Sign in one hardware operation
  String? signature;
  try {
    signature = await CryptoService.signData('$sessionId:$qrToken');
    if (signature == null) {
      _showError('Authentication cancelled');
      return;
    }
  } catch (e) {
    _showError('Authentication failed. Please try again.');
    return;
  }

    setState(() {
      _statusMessage = 'Marking attendance...';
      _statusSubMessage = 'Please wait...';
    });

    // Step 3: Send to server
    try {
      final result = await ApiService.markAttendance(
      sessionId: sessionId,
      qrToken: qrToken,
      signature: signature,
      scanTimestamp: scanTimestamp,
    );

      if (result['status'] == 201) {
        setState(() {
          _scanComplete = true;
          _isProcessing = false;
          _isSuccess = true;
          _isError = false;
          _statusMessage = 'Attendance Marked!';
          _statusSubMessage =
              result['data']['subject'] ?? 'Successfully recorded';
        });
      } else {
        _showError(result['data']['error'] ?? 'Failed to mark attendance');
      }
    } catch (e) {
      _showError('Connection error. Please try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _isError = true;
      _isSuccess = false;
      _statusMessage = 'Failed';
      _statusSubMessage = message;
      _scanComplete = false;
    });

    // Resume scanner after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isError = false;
          _statusMessage = 'Point camera at QR code';
          _statusSubMessage = '';
        });
        _scannerController.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Camera view
          if (!_isSuccess)
            MobileScanner(
              controller: _scannerController,
              onDetect: _onQRDetected,
            ),

          // Success screen
          if (_isSuccess)
            Container(
              color: const Color(0xFF0A0A0F),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C896).withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00C896),
                          width: 3,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Color(0xFF00C896),
                        size: 50,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Attendance Marked!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusSubMessage,
                      style: const TextStyle(
                        color: Color(0xFF8A8A9A),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          'DONE',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Overlay — scan frame
          if (!_isSuccess)
            Container(
              decoration: ShapeDecoration(
                shape: QRScannerOverlay(
                  borderColor: _isError
                      ? const Color(0xFFFF5C38)
                      : _isProcessing
                          ? const Color(0xFFFFAA00)
                          : const Color(0xFF00C896),
                  borderRadius: 12,
                  borderLength: 30,
                  borderWidth: 4,
                  cutOutSize: 250,
                ),
              ),
            ),

          // Status message at bottom
          if (!_isSuccess)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if (_isProcessing)
                    const CircularProgressIndicator(
                      color: Color(0xFF00C896),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _isError
                          ? const Color(0xFFFF5C38)
                          : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_statusSubMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _statusSubMessage,
                        style: const TextStyle(
                          color: Color(0xFF8A8A9A),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
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

// QR Scanner overlay shape
class QRScannerOverlay extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QRScannerOverlay({
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.borderLength,
    required this.cutOutSize,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final center = rect.center;
    final cutOutRect = Rect.fromCenter(
      center: center,
      width: cutOutSize,
      height: cutOutSize,
    );

    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(
          cutOutRect,
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final center = rect.center;
    final cutOutRect = Rect.fromCenter(
      center: center,
      width: cutOutSize,
      height: cutOutSize,
    );

    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    // Draw dark overlay
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addRRect(
          RRect.fromRectAndRadius(
            cutOutRect,
            Radius.circular(borderRadius),
          ),
        ),
      paint,
    );

    // Draw corner borders
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final left = cutOutRect.left;
    final top = cutOutRect.top;
    final right = cutOutRect.right;
    final bottom = cutOutRect.bottom;

    // Top left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + borderLength)
        ..lineTo(left, top + borderRadius)
        ..arcToPoint(Offset(left + borderRadius, top),
            radius: Radius.circular(borderRadius))
        ..lineTo(left + borderLength, top),
      borderPaint,
    );

    // Top right
    canvas.drawPath(
      Path()
        ..moveTo(right - borderLength, top)
        ..lineTo(right - borderRadius, top)
        ..arcToPoint(Offset(right, top + borderRadius),
            radius: Radius.circular(borderRadius))
        ..lineTo(right, top + borderLength),
      borderPaint,
    );

    // Bottom left
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - borderLength)
        ..lineTo(left, bottom - borderRadius)
        ..arcToPoint(Offset(left + borderRadius, bottom),
            radius: Radius.circular(borderRadius),
            clockwise: false)
        ..lineTo(left + borderLength, bottom),
      borderPaint,
    );

    // Bottom right
    canvas.drawPath(
      Path()
        ..moveTo(right - borderLength, bottom)
        ..lineTo(right - borderRadius, bottom)
        ..arcToPoint(Offset(right, bottom - borderRadius),
            radius: Radius.circular(borderRadius),
            clockwise: false)
        ..lineTo(right, bottom - borderLength),
      borderPaint,
    );
  }

  @override
  ShapeBorder scale(double t) => this;
}
