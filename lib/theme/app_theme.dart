import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// AppTheme class to define consistent styles across the app
class AppTheme {
  // Colors
  static const Color primaryColor = Color(0xFF3F51B5); // Blue
  static const Color accentColor = Color(0xFFFFC107); // Amber
  static const Color backgroundColor = Color(0xFFF5F7FA); // Light gray

  // Gradient for buttons and backgrounds
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3F51B5), Color(0xFF7986CB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Text styles using Poppins font
  static TextStyle headline = GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static TextStyle subtitle = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: Colors.white70,
  );

  static TextStyle body = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: Colors.black87,
  );

  static TextStyle buttonText = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  // Input decoration for text fields
  static InputDecoration textFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: body.copyWith(color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // Button style
  static ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.transparent,
    foregroundColor: accentColor,
    shadowColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 0,
  );

  // Theme data for the app
  static ThemeData lightTheme = ThemeData(
    primaryColor: primaryColor,
    scaffoldBackgroundColor: backgroundColor,
    textTheme: TextTheme(
      headlineLarge: headline,
      bodyMedium: body,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: elevatedButtonStyle),
  );
}