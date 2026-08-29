import 'package:flutter/material.dart';

/// LocalLink Design System
///
/// All UI colours should come from this file.
/// Avoid using Colors.black, Colors.white, Colors.grey etc.
/// This keeps the entire app visually consistent.

class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  /// LocalLink Orange
  static const Color primary = Color(0xFFF26A2E);

  /// Activities: free community and social opportunities
  static const Color activityBlue = Color(0xFF2563EB);

  /// Services: paid provider/customer service opportunities
  static const Color serviceGreen = Color(0xFF168A5A);

  // ---------------------------------------------------------------------------
  // Backgrounds
  // ---------------------------------------------------------------------------

  /// Main app background
  static const Color background = Color(0xFFF9F6F2);

  /// Cards & sheets
  static const Color card = Color(0xFFFFFFFF);

  /// Slightly darker background for grouped sections
  static const Color surface = Color(0xFFF3EFEA);

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  /// Primary text
  static const Color charcoal = Color(0xFF1E1E1E);

  /// Secondary text
  static const Color textMuted = Color(0xFF6F6F6F);

  /// Very subtle text/placeholders
  static const Color textLight = Color(0xFF9E9E9E);

  // ---------------------------------------------------------------------------
  // Borders & Dividers
  // ---------------------------------------------------------------------------

  static const Color divider = Color(0xFFE6E1DA);

  static const Color border = Color(0xFFE0DBD4);

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  static const Color success = Color(0xFF2E7D5B);

  static const Color error = Color(0xFFC64545);

  static const Color warning = Color(0xFFF2A93B);

  static const Color info = Color(0xFF4B82F1);

  // ---------------------------------------------------------------------------
  // Buttons
  // ---------------------------------------------------------------------------

  /// Default primary button
  static const Color buttonPrimary = charcoal;

  static const Color buttonText = Colors.white;

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

  /// Used for disabled buttons/icons
  static const Color disabled = Color(0xFFCFC8BF);

  /// Very subtle shadows
  static const Color shadow = Color(0x14000000);
}
