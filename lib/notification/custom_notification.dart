import 'package:flutter/material.dart';

enum NotificationType {
  success,
  error,
  warning,
  info,
  emailNotFound,
}

class CustomNotification extends StatefulWidget {
  final String message;
  final bool isError;
  final NotificationType type;

  const CustomNotification({
    super.key,
    required this.message,
    this.isError = true,
    this.type = NotificationType.error,
  });

  @override
  State<CustomNotification> createState() => _CustomNotificationState();
}

class _CustomNotificationState extends State<CustomNotification> 
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _bounceController;
  late AnimationController _shimmerController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Slide animation controller
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    // Bounce animation controller
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // Shimmer animation controller
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Slide animation
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    // Bounce animation
    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.bounceOut,
    ));

    // Shimmer animation
    _shimmerAnimation = Tween<double>(
      begin: -2.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.linear,
    ));

    // Fade animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    // Start animations
    _slideController.forward();
    _bounceController.forward();
    
    // Start shimmer for success notifications
    if (!widget.isError && widget.type == NotificationType.success) {
      _shimmerController.repeat();
    }

    // Auto-dismiss after delay (longer for success messages)
    final dismissDelay = widget.type == NotificationType.success 
        ? const Duration(seconds: 3) 
        : const Duration(seconds: 4);
        
    Future.delayed(dismissDelay, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    await _slideController.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Color _getBackgroundColor() {
    switch (widget.type) {
      case NotificationType.success:
        return const Color(0xFF4CAF50);
      case NotificationType.error:
        return const Color(0xFFF44336);
      case NotificationType.warning:
        return const Color(0xFFFF9800);
      case NotificationType.info:
        return const Color(0xFF2196F3);
      case NotificationType.emailNotFound:
        return const Color(0xFFE91E63);
    }
  }

  Color _getAccentColor() {
    switch (widget.type) {
      case NotificationType.success:
        return const Color(0xFF66BB6A);
      case NotificationType.error:
        return const Color(0xFFEF5350);
      case NotificationType.warning:
        return const Color(0xFFFFB74D);
      case NotificationType.info:
        return const Color(0xFF42A5F5);
      case NotificationType.emailNotFound:
        return const Color(0xFFEC407A);
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.error:
        return Icons.error_rounded;
      case NotificationType.warning:
        return Icons.warning_rounded;
      case NotificationType.info:
        return Icons.info_rounded;
      case NotificationType.emailNotFound:
        return Icons.person_search_rounded;
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _bounceController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _bounceAnimation,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 50, 16, 0),
                  child: Stack(
                    children: [
                      // Main notification container
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _getBackgroundColor(),
                              _getAccentColor(),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _getBackgroundColor().withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Icon container
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getIcon(),
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Message
                            Expanded(
                              child: Text(
                                widget.message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Close button
                            GestureDetector(
                              onTap: _dismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Shimmer effect for success notifications
                      if (widget.type == NotificationType.success)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedBuilder(
                              animation: _shimmerAnimation,
                              builder: (context, child) {
                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.transparent,
                                        Colors.white.withOpacity(0.1),
                                        Colors.transparent,
                                      ],
                                      stops: [
                                        0.0,
                                        _shimmerAnimation.value.clamp(0.0, 1.0),
                                        1.0,
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      // Decorative elements
                      Positioned(
                        top: -10,
                        right: -10,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -5,
                        left: -5,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}