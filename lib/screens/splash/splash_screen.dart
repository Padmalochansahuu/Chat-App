import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../Auth/login_screen.dart';
import '../Home/home_screen.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller for zoom effect
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();

    // Check session after animation
    _checkSession();
  }

  void _checkSession() async {
    await Future.delayed(const Duration(seconds: 2)); // Allow animation to complete
    final user = await AuthService().checkSession();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => user != null ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icon/icon.png',
                  width: 150,
                  height: 150,
                ),
                const SizedBox(height: 24),
                Text(
                  'Chat App',
                  style: AppTheme.headline.copyWith(fontSize: 36),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect Instantly',
                  style: AppTheme.subtitle.copyWith(fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}