import 'package:chatapp/connection/network_check.dart';
import 'package:chatapp/connection/network_screen.dart';
import 'package:chatapp/screens/Auth/forgot_password_modal.dart';
import 'package:chatapp/screens/Auth/login_screen.dart';
import 'package:chatapp/screens/Auth/registration_screen.dart';
import 'package:chatapp/screens/Home/home_screen.dart';
import 'package:chatapp/screens/chat/chat_screen.dart';
import 'package:chatapp/screens/chat/group.dart';
import 'package:chatapp/screens/profile/profile_screen.dart';
import 'package:chatapp/screens/splash/splash_screen.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    if (e.toString().contains('[core/duplicate-app]')) {
      print('Firebase already initialized - using existing instance');
    } else {
      print('Firebase initialization error: $e');
      rethrow;
    }
  }

  final authService = AuthService();
  authService.initialize();
  await NetworkCheck().init();
  runApp(MyApp(authService: authService));
}

class GlobalRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateLastRoute(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _updateLastRoute(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _updateLastRoute(previousRoute);
    }
    super.didPop(route, previousRoute);
  }

  void _updateLastRoute(Route<dynamic> route) {
    if (!kIsWeb && route.settings.name != null && route.settings.name != '/network') {
      NetworkCheck().setLastRoute(route.settings.name, route.settings.arguments);
    }
  }
}

class MyApp extends StatefulWidget {
  final AuthService authService;

  const MyApp({super.key, required this.authService});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalRouteObserver _routeObserver = GlobalRouteObserver();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_navigatorKey.currentContext != null) {
          NetworkCheck().setNavigationContext(_navigatorKey.currentContext!);
        }
      });
    }
    widget.authService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NetworkCheck().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      widget.authService.initialize();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      widget.authService.updatePresence(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Chat App',
        theme: AppTheme.lightTheme,
        navigatorKey: _navigatorKey,
        navigatorObservers: [_routeObserver],
        home: const SplashScreen(),
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/registration': (context) => const RegistrationScreen(),
          '/forgot_password': (context) => const ForgotPasswordScreen(),
          '/home': (context) => const HomeScreen(),
          '/chat': (context) => const ChatScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/group': (context) => const GroupCreationScreen(),
        },
      );
    }

    return StreamBuilder<bool>(
      stream: NetworkCheck().connectivityStream,
      initialData: NetworkCheck().isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? true;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Chat App',
          theme: AppTheme.lightTheme,
          navigatorKey: _navigatorKey,
          navigatorObservers: [_routeObserver],
          home: NetworkAwareWrapper(isConnected: isConnected),
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/registration': (context) => const RegistrationScreen(),
            '/forgot_password': (context) => const ForgotPasswordScreen(),
            '/home': (context) => const HomeScreen(),
            '/chat': (context) => const ChatScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/group': (context) => const GroupCreationScreen(),
          },
        );
      },
    );
  }
}

class NetworkAwareWrapper extends StatefulWidget {
  final bool isConnected;

  const NetworkAwareWrapper({
    super.key,
    required this.isConnected,
  });

  @override
  State<NetworkAwareWrapper> createState() => NetworkAwareWrapperState();
}

class NetworkAwareWrapperState extends State<NetworkAwareWrapper> {
  Widget? _lastScreen;
  bool _wasConnected = true;

  @override
  void initState() {
    super.initState();
    _wasConnected = widget.isConnected;
    if (widget.isConnected) {
      _lastScreen = const SplashScreen();
    }
  }

  @override
  void didUpdateWidget(NetworkAwareWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isConnected != widget.isConnected) {
      if (!widget.isConnected) {
        setState(() {
          _wasConnected = false;
        });
      } else if (!_wasConnected && widget.isConnected) {
        _navigateToLastScreen();
      }
    }
  }

  void _navigateToLastScreen() {
    final lastRoute = NetworkCheck().lastRouteName;
    final lastArguments = NetworkCheck().lastRouteArguments;

    if (lastRoute != null && lastRoute != '/') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            lastRoute,
            (route) => false,
            arguments: lastArguments,
          );
        }
      });
    } else {
      setState(() {
        _lastScreen = const SplashScreen();
        _wasConnected = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NetworkCheck().setNavigationContext(context);
      });
    } 
    if (!widget.isConnected) {
      return const NetworkScreen();
    }

    if (widget.isConnected && _lastScreen == null) {
      _lastScreen = const SplashScreen();
    }

    return _lastScreen ?? const SplashScreen();
  }
}