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
  static const Color primarySoft = Color(0xFFFFECE3);

  /// Deeper terracotta used for high-emphasis brand surfaces.
  static const Color primaryDeep = Color(0xFFB8522F);

  /// Activities: free community and social opportunities
  static const Color activityBlue = Color(0xFF2563EB);
  static const Color activitySoft = Color(0xFFEAF1FF);

  /// Services: paid provider/customer service opportunities
  static const Color serviceGreen = Color(0xFF168A5A);
  static const Color serviceSoft = Color(0xFFE8F5EF);

  /// Neighbour-to-neighbour help, lost/found, and free items.
  static const Color communityTeal = Color(0xFF0E7C71);
  static const Color communitySoft = Color(0xFFE6F4F1);

  // ---------------------------------------------------------------------------
  // Backgrounds
  // ---------------------------------------------------------------------------

  /// Main app background
  static const Color background = Color(0xFFF9F6F2);

  /// Cards & sheets
  static const Color card = Color(0xFFFFFFFF);

  /// Warm raised surface for inset controls and highlighted groups.
  static const Color elevatedSurface = Color(0xFFFFFCF8);

  /// Slightly darker background for grouped sections
  static const Color surface = Color(0xFFF3EFEA);

  /// Quiet secondary surface for disabled or non-primary controls.
  static const Color secondarySurface = Color(0xFFF6F1EA);

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  /// Primary text
  static const Color charcoal = Color(0xFF1E1E1E);

  /// Secondary text
  static const Color textMuted = Color(0xFF6F6F6F);

  /// Very subtle text/placeholders
  static const Color textLight = Color(0xFF9E9E9E);

  /// Text on tinted or deeply coloured surfaces.
  static const Color inverseText = Color(0xFFFFFFFF);

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

  static const Color lost = Color(0xFFC64545);

  static const Color lostSoft = Color(0xFFFFECEC);

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
