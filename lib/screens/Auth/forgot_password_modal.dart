import 'package:chatapp/error/error_messages.dart';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> 
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
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
      CurvedAnimation(
        parent: _controller, 
        curve: const Interval(0.2, 1, curve: Curves.easeInOut)
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  // void _sendResetEmail() async {
  //   if (_formKey.currentState!.validate()) {
  //     setState(() => _isLoading = true);

  //     try {
  //       final email = _emailController.text.trim().toLowerCase();
  //       print('Attempting to send password reset email for: $email');
        
  //       await AuthService().sendPasswordResetEmail(email);

  //       if (mounted) {
  //         print('Password reset email sent successfully for: $email');
  //         showDialog(
  //           context: context,
  //           barrierDismissible: false,
  //           builder: (_) => const CustomNotification(
  //             message: '🎉 Password reset link sent to your email!',
  //             isError: false,
  //             type: NotificationType.success,
  //           ),
  //         );
          
  //         await Future.delayed(const Duration(seconds: 2));
          
  //         if (mounted) {
  //           Navigator.of(context).pop(); // Close notification
  //           Navigator.of(context).pop(); // Back to login
  //         }
  //       }
  //     } catch (e) {
  //       print('Error sending password reset email: $e');
  //       if (mounted) {
  //         String errorMessage = getFriendlyErrorMessage(e);
  //         print('Friendly error message displayed to user: $errorMessage');
  //         showDialog(
  //           context: context,
  //           barrierDismissible: false,
  //           builder: (_) => CustomNotification(
  //             message: '❌ $errorMessage',
  //             isError: true,
  //             type: errorMessage.contains('No account found') 
  //                 ? NotificationType.emailNotFound 
  //                 : NotificationType.error,
  //           ),
  //         );
          
  //         await Future.delayed(const Duration(seconds: 3));
  //         if (mounted) {
  //           Navigator.of(context).pop(); // Close error notification
  //         }
  //       }
  //     }

  //     if (mounted) {
  //       setState(() => _isLoading = false);
  //     }
  //   }
  // }

// Updated _sendResetEmail method in forgot_password_modal.dart
// This approach is more reliable and user-friendly

void _sendResetEmail() async {
  if (_formKey.currentState!.validate()) {
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim().toLowerCase();
      print('Attempting to send password reset email for: $email');
      
      // Approach 1: Try direct password reset (recommended)
      // Firebase handles existence check internally and won't expose user info
      await AuthService().sendPasswordResetEmail(email);

      if (mounted) {
        print('Password reset email request processed for: $email');
        
        // Show success message regardless of whether email exists
        // This is a security best practice to not reveal user information
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => CustomNotification(
            message: '📧 If an account with this email exists, a password reset link has been sent.',
            isError: false,
            type: NotificationType.success,
          ),
        );
        
        await Future.delayed(const Duration(seconds: 3));
        
        if (mounted) {
          Navigator.of(context).pop(); // Close notification
          Navigator.of(context).pop(); // Back to login
        }
      }
    } catch (e) {
      print('Error sending password reset email: $e');
      if (mounted) {
        String errorMessage = getFriendlyErrorMessage(e);
        print('Friendly error message displayed to user: $errorMessage');
        
        // Only show specific errors for technical issues, not user existence
        NotificationType notificationType = NotificationType.error;
        if (errorMessage.contains('Too many requests')) {
          notificationType = NotificationType.warning;
        } else if (errorMessage.contains('Network error') || 
                   errorMessage.contains('connection')) {
          notificationType = NotificationType.warning;
        }
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => CustomNotification(
            message: '❌ $errorMessage',
            isError: true,
            type: notificationType,
          ),
        );
        
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.of(context).pop(); // Close error notification
        }
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

// Alternative approach if you want to verify email existence first


  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
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
            // Calculate responsive padding and max width
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
                          // Forgot password icon
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
                            child: Icon(
                              Icons.lock_reset_rounded,
                              size: iconSize,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Forgot Password?',
                            style: AppTheme.headline.copyWith(
                              fontSize: 24 * textScaleFactor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter your registered email address and we\'ll send you a link to reset your password',
                            style: AppTheme.subtitle.copyWith(
                              fontSize: 14 * textScaleFactor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
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
                          const SizedBox(height: 24),
                          // Send Reset Email button
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
                                onPressed: _isLoading ? null : _sendResetEmail,
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      )
                                    : Text(
                                        'Send Reset Link',
                                        style: AppTheme.buttonText.copyWith(
                                          fontSize: 16 * textScaleFactor,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Info text
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.white.withOpacity(0.8),
                                  size: 20 * textScaleFactor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Reset link will only be sent to registered email addresses',
                                    style: AppTheme.body.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 12 * textScaleFactor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Back to login link
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 18 * textScaleFactor,
                            ),
                            label: Text(
                              'Back to Login',
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
  }}