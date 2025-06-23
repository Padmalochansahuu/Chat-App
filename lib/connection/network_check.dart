

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb

class NetworkCheck {
  static final NetworkCheck _instance = NetworkCheck._internal();
  factory NetworkCheck() => _instance;
  NetworkCheck._internal();

  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _controller.stream;
  
  bool _isConnected = true;
  bool get isConnected => _isConnected;
  
  // Store last route information
  String? _lastRouteName;
  Object? _lastRouteArguments;
  
  // Navigation context for global navigation
  BuildContext? _navigationContext;
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectionTimer;

  Future<void> init() async {
    // Skip network checking for web platform
    if (kIsWeb) {
      _isConnected = true;
      _controller.add(true);
      return;
    }

    // Initial check for mobile platforms
    await checkConnection();
    
    // Listen for connectivity changes with debouncing (mobile only)
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      _debounceConnectionCheck();
    });
  }

  void _debounceConnectionCheck() {
    // Skip debouncing for web
    if (kIsWeb) return;
    
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(milliseconds: 500), () {
      checkConnection();
    });
  }

  Future<bool> checkConnection() async {
    // Always return true for web platform
    if (kIsWeb) {
      _updateStatus(true);
      return true;
    }

    try {
      // Check network type first (mobile only)
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none) || results.isEmpty) {
        _updateStatus(false);
        return false;
      }

      // Verify actual internet access with multiple fallbacks (mobile only)
      final futures = [
        _testConnection('https://www.google.com'),
        _testConnection('https://www.cloudflare.com'),
        _testConnection('https://8.8.8.8'),
      ];

      try {
        final testResults = await Future.wait(futures, eagerError: false);
        final isConnected = testResults.any((result) => result);
        _updateStatus(isConnected);
        return isConnected;
      } catch (e) {
        _updateStatus(false);
        return false;
      }
    } catch (e) {
      _updateStatus(false);
      return false;
    }
  }

  Future<bool> _testConnection(String url) async {
    // Skip actual testing for web
    if (kIsWeb) return true;
    
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 3),
        onTimeout: () => http.Response('Timeout', 408),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void _updateStatus(bool isConnected) {
    if (_isConnected != isConnected) {
      final wasConnected = _isConnected;
      _isConnected = isConnected;
      _controller.add(isConnected);
      
      // Handle automatic navigation (mobile only)
      if (!kIsWeb && !wasConnected && isConnected && _navigationContext != null) {
        _handleReconnection();
      }
    }
  }

  void _handleReconnection() {
    // Skip reconnection handling for web
    if (kIsWeb) return;
    
    if (_navigationContext != null && _lastRouteName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          // Check if the context is still valid
          if (_navigationContext!.mounted) {
            Navigator.of(_navigationContext!).pushNamedAndRemoveUntil(
              _lastRouteName!,
              (route) => false,
              arguments: _lastRouteArguments,
            );
          }
        } catch (e) {
          debugPrint('Error navigating back: $e');
        }
      });
    }
  }

  // Call this method to store the last route (mobile only)
  void setLastRoute(String? routeName, Object? arguments) {
    if (kIsWeb) return; // Skip for web
    
    if (routeName != null && routeName != '/network') {
      _lastRouteName = routeName;
      _lastRouteArguments = arguments;
    }
  }

  // Set navigation context for global navigation (mobile only)
  void setNavigationContext(BuildContext context) {
    if (kIsWeb) return; // Skip for web
    _navigationContext = context;
  }

  // Get last route information
  String? get lastRouteName => _lastRouteName;
  Object? get lastRouteArguments => _lastRouteArguments;

  // Check if platform supports network monitoring
  bool get supportsNetworkMonitoring => !kIsWeb;

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectionTimer?.cancel();
    _controller.close();
  }
}