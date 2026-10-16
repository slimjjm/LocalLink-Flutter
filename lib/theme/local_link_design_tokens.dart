import 'package:flutter/material.dart';

import 'app_colors.dart';

class LocalLinkSpacing {
  const LocalLinkSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class LocalLinkRadius {
  const LocalLinkRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double sheet = 28;
  static const double pill = 999;
}

class LocalLinkBorders {
  const LocalLinkBorders._();

  static const BorderSide standard = BorderSide(color: AppColors.border);
  static BorderSide subtle = BorderSide(
    color: AppColors.border.withValues(alpha: 0.72),
  );
  static BorderSide selected(Color color) =>
      BorderSide(color: color.withValues(alpha: 0.34), width: 1.2);
}

class LocalLinkDepth {
  const LocalLinkDepth._();

  static List<BoxShadow> get subtle => [
    BoxShadow(
      color: AppColors.charcoal.withValues(alpha: 0.045),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get floating => [
    BoxShadow(
      color: AppColors.charcoal.withValues(alpha: 0.10),
      blurRadius: 26,
      offset: const Offset(0, 14),
    ),
  ];
}

class LocalLinkMotion {
  const LocalLinkMotion._();

  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration calm = Duration(milliseconds: 320);

  static const Curve curve = Curves.easeOutCubic;
}

class LocalLinkTextStyles {
  const LocalLinkTextStyles._();

  static const TextStyle screenTitle = TextStyle(
    color: AppColors.charcoal,
    fontSize: 30,
    height: 1.04,
    fontWeight: FontWeight.w900,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: AppColors.charcoal,
    fontSize: 22,
    height: 1.12,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle cardTitle = TextStyle(
    color: AppColors.charcoal,
    fontSize: 17,
    height: 1.18,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.charcoal,
    fontSize: 15,
    height: 1.36,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle bodyStrong = TextStyle(
    color: AppColors.charcoal,
    fontSize: 15,
    height: 1.28,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle secondary = TextStyle(
    color: AppColors.textMuted,
    fontSize: 14,
    height: 1.34,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle metadata = TextStyle(
    color: AppColors.textMuted,
    fontSize: 13,
    height: 1.24,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle label = TextStyle(
    color: AppColors.charcoal,
    fontSize: 13,
    height: 1.18,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle status = TextStyle(
    fontSize: 11,
    height: 1.1,
    letterSpacing: 0,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 1.1,
    letterSpacing: 0,
    fontWeight: FontWeight.w800,
  );
}
