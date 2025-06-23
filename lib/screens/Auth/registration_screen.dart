import 'package:chatapp/error/error_messages.dart';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/screens/Auth/login_screen.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:flutter/material.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 1, curve: Curves.easeInOut)),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  void _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final email = _emailController.text.trim().toLowerCase(); // Normalize email
        print('Attempting to register with email: $email');
        final user = await AuthService().register(
          _nameController.text.trim(),
          email,
          _passwordController.text,
        );
        if (user != null && mounted) {
          print('Registration successful, redirecting to login screen');
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const CustomNotification(
              message: '🎉 Registration successful! Redirecting to login screen...',
              isError: false,
              type: NotificationType.success,
            ),
          );
          
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop(); // Close notification
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(
                  skipSessionCheck: true, // Pass flag to skip session check
                ),
              ),
            );
          }
        }
      } catch (e) {
        print('Registration error: $e');
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

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    extendBodyBehindAppBar: true,
    body: Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 600 ? 400.0 : constraints.maxWidth * 0.9;
            final padding = constraints.maxWidth > 600 ? 32.0 : 24.0;
            final iconSize = constraints.maxWidth > 600 ? 70.0 : 60.0;
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
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/icon/icon.png',
                              width: iconSize,
                              height: iconSize,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Create Account',
                            style: AppTheme.headline.copyWith(
                              fontSize: 24 * textScaleFactor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Join the chat community',
                            style: AppTheme.subtitle.copyWith(
                              fontSize: 14 * textScaleFactor,
                            ),
                          ),
                          const SizedBox(height: 32),
                          // Name field
                          TextFormField(
                            controller: _nameController,
                            decoration: AppTheme.textFieldDecoration('Name').copyWith(
                              prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                            ),
                            style: TextStyle(fontSize: 16 * textScaleFactor),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your name.';
                              }
                              if (value.trim().length < 2) {
                                return 'Name must be at least 2 characters.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Email field
                          TextFormField(
                            controller: _emailController,
                            decoration: AppTheme.textFieldDecoration('Email').copyWith(
                              prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
                            ),
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
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
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
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Confirm password field
                          TextFormField(
                            controller: _confirmPasswordController,
                            decoration:
                                AppTheme.textFieldDecoration('Confirm Password').copyWith(
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                  size: 20 * textScaleFactor,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscureConfirmPassword,
                            style: TextStyle(fontSize: 16 * textScaleFactor),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password.';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          // Register button
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: AppTheme.elevatedButtonStyle.copyWith(
                                  minimumSize: WidgetStateProperty.all(
                                    Size(double.infinity, 50 * textScaleFactor),
                                  ),
                                ),
                                onPressed: _isLoading ? null : _register,
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      )
                                    : Text(
                                        'Register',
                                        style: AppTheme.buttonText.copyWith(
                                          fontSize: 16 * textScaleFactor,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Login link
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            icon: Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 18 * textScaleFactor,
                            ),
                            label: Text(
                              'Already have an account? Login',
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
  ));
  }
}