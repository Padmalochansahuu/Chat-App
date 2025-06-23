import 'package:chatapp/error/error_messages.dart';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'registration_screen.dart';
import 'forgot_password_modal.dart';

import '../Home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool skipSessionCheck; // Added parameter to skip session check

  const LoginScreen({super.key, this.skipSessionCheck = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Check session only if skipSessionCheck is false
    if (!widget.skipSessionCheck) {
      _checkSession();
    }
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  void _checkSession() async {
    final user = await AuthService().checkSession();
    if (user != null && mounted) {
      print('Session check: User found, navigating to HomeScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      print('Session check: No user found');
    }
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final email = _emailController.text.trim().toLowerCase(); // Normalize email
        print('Attempting to login with email: $email');
        final user = await AuthService().login(
          email,
          _passwordController.text,
        );
        if (user != null && mounted) {
          print('Login successful, navigating to HomeScreen');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } catch (e) {
        print('Login error: $e');
        if (mounted) {
          String errorMessage = getFriendlyErrorMessage(e);
          print('Friendly error message displayed to user: $errorMessage');
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => CustomNotification(
              message: '❌ $errorMessage',
              isError: true,
              type: NotificationType.error,
            ),
          );
        }
      }
      setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 600 ? 400.0 : constraints.maxWidth * 0.9;
            final padding = constraints.maxWidth > 600 ? 32.0 : 24.0;
            final iconSize = constraints.maxWidth > 600 ? 120.0 : 100.0;
            final textScaleFactor = constraints.maxWidth > 1200 ? 1.2 : 1.0;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // App logo
                          Image.asset(
                            'assets/icon/icon.png',
                            width: iconSize,
                            height: iconSize,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chat App',
                            style: AppTheme.headline.copyWith(
                              fontSize: 24 * textScaleFactor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connect with friends',
                            style: AppTheme.subtitle.copyWith(
                              fontSize: 14 * textScaleFactor,
                            ),
                          ),
                          const SizedBox(height: 32),
                          // Email field
                          TextFormField(
                            controller: _emailController,
                            decoration: AppTheme.textFieldDecoration('Email'),
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(fontSize: 16 * textScaleFactor),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your email.';
                              }
                              if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                                  .hasMatch(value.trim())) {
                                return 'Please enter a valid email.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Password field
                          TextFormField(
                            controller: _passwordController,
                            decoration: AppTheme.textFieldDecoration('Password').copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.grey,
                                  size: 20 * textScaleFactor,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscurePassword,
                            style: TextStyle(fontSize: 16 * textScaleFactor),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          // Forgot Password link
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordScreen,
                              child: Text(
                                'Forgot Password?',
                                style: AppTheme.body.copyWith(
                                  color: Colors.white,
                                  fontSize: 14 * textScaleFactor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Login button
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: AppTheme.elevatedButtonStyle.copyWith(
                                  minimumSize: WidgetStateProperty.all(
                                    Size(double.infinity, 50 * textScaleFactor),
                                  ),
                                ),
                                onPressed: _isLoading ? null : _login,
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      )
                                    : Text(
                                        'Login',
                                        style: AppTheme.buttonText.copyWith(
                                          fontSize: 16 * textScaleFactor,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Sign up link
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegistrationScreen()),
                              );
                            },
                            child: Text(
                              'Don\'t have an account? Sign Up',
                              style: AppTheme.body.copyWith(
                                color: Colors.white,
                                fontSize: 14 * textScaleFactor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
   ) );
  }
}