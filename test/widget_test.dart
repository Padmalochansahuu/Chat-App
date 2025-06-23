
import 'package:chatapp/main.dart';
import 'package:chatapp/screens/splash/splash_screen.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp/firebase_options.dart';

void main() {
  setUpAll(() async {
    // Initialize Firebase for tests
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      if (!e.toString().contains('[core/duplicate-app]')) {
        rethrow;
      }
    }
  });

  testWidgets('SplashScreen loads without crashing', (WidgetTester tester) async {
    // Arrange: Create AuthService instance
    final authService = AuthService();

    // Act: Build the app with AuthService and trigger a frame
    await tester.pumpWidget(MyApp(authService: authService));

    // Assert: Verify the app loads (SplashScreen is displayed)
    expect(find.byType(SplashScreen), findsOneWidget);

    // Pump for a short duration to ensure stability
    await tester.pump(const Duration(seconds: 1));
  });
}