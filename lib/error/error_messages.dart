import 'package:firebase_auth/firebase_auth.dart';

String getFriendlyErrorMessage(dynamic error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'weak-password':
        return 'Password must be at least 6 characters long.';
      case 'invalid-credential':
        return 'Invalid credentials. Please check your email and password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'operation-not-allowed':
        return 'This operation is not allowed. Please contact support.';
      default:
        return 'An error occurred. Please try again later.';
    }
  }
  return 'Something went wrong. Please try again.';
}