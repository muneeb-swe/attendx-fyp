import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _subtitleController;

  late Animation<double> _logoFade;
  late Animation<double> _subtitleFade;
  late Animation<Offset> _subtitleSlide;

  @override
  void initState() {
    super.initState();

    // Logo fade controller
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Subtitle controller — starts after logo
    _subtitleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Logo fades in
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeIn,
      ),
    );

    // Subtitle fades in
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _subtitleController,
        curve: Curves.easeIn,
      ),
    );

    // Subtitle slides up
    _subtitleSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _subtitleController,
        curve: Curves.easeOut,
      ),
    );

    _startAnimation();
  }

  Future<void> _startAnimation() async {
    // Wait a moment then fade logo in
    await Future.delayed(const Duration(milliseconds: 300));
    await _logoController.forward();

    // Then slide subtitle up
    await Future.delayed(const Duration(milliseconds: 200));
    await _subtitleController.forward();

    // Wait then navigate to login
    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            FadeTransition(
              opacity: _logoFade,
              child: Column(
                children: [
                  // Icon circle
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00C896),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner,
                      color: Color(0xFF00C896),
                      size: 44,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // App name
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
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
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Subtitle slides up
            SlideTransition(
              position: _subtitleSlide,
              child: FadeTransition(
                opacity: _subtitleFade,
                child: const Text(
                  'Secure Attendance System',
                  style: TextStyle(
                    color: Color(0xFF8A8A9A),
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}