import 'package:chatapp/connection/network_check.dart';
import 'package:flutter/material.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'dart:async';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  
  bool _isRetrying = false;
  Timer? _autoRetryTimer;
  int _retryCount = 0;
  final int _maxAutoRetries = 3;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAutoRetry();
  }

  void _setupAnimations() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
      ),
    );
    
    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear,
      ),
    );
    
    _controller.forward();
  }

  void _startAutoRetry() {
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_retryCount < _maxAutoRetries && mounted) {
        _retryCount++;
        _retryConnection();
      } else {
        timer.cancel();
      }
    });
  }

  void _retryConnection() async {
    if (_isRetrying) return;
    
    setState(() {
      _isRetrying = true;
    });

    // Add visual feedback
    _controller.reset();
    _controller.forward();

    try {
      await NetworkCheck().checkConnection();
      
      // Small delay to show the retry animation
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      debugPrint('Retry failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  void _manualRetry() {
    _retryCount = 0; // Reset auto-retry counter on manual retry
    _retryConnection();
  }

  @override
  void dispose() {
    _controller.dispose();
    _autoRetryTimer?.cancel();
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
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated WiFi off icon
                    _buildAnimatedIcon(),
                    const SizedBox(height: 32),
                    
                    // Title
                    Text(
                      'No Internet Connection',
                      style: AppTheme.headline.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.3),
                            offset: const Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    
                    // Subtitle
                    Text(
                      'Please check your internet connection\nand try again.',
                      style: AppTheme.subtitle.copyWith(
                        fontSize: 16,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    
                    // Status indicator
                    _buildStatusIndicator(),
                    const SizedBox(height: 24),
                    
                    // Retry button
                    _buildRetryButton(),
                    const SizedBox(height: 16),
                    
                    // Auto-retry info
                    if (_retryCount < _maxAutoRetries)
                      Text(
                        'Auto-retrying... (${_retryCount}/$_maxAutoRetries)',
                        style: AppTheme.subtitle.copyWith(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.1),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: _isRetrying
          ? RotationTransition(
              turns: _rotationAnimation,
              child: const Icon(
                Icons.refresh_rounded,
                size: 60,
                color: Colors.white,
              ),
            )
          : const Icon(
              Icons.wifi_off_rounded,
              size: 60,
              color: Colors.white,
            ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isRetrying ? 'Checking connection...' : 'Disconnected',
            style: AppTheme.subtitle.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        onPressed: _isRetrying ? null : _manualRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRetrying) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryColor.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ] else ...[
              const Icon(Icons.refresh_rounded, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              _isRetrying ? 'Retrying...' : 'Retry Connection',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}