import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../theme/app_colors.dart';

class LocalLinkMarker {
  static Future<BitmapDescriptor> build({
    required String category,
    required int attendeeCount,
    required bool selected,
  }) async {
    const markerWidth = 180.0;
    const markerHeight = 120.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 14, 160, 64),
        const Radius.circular(22),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: selected ? .22 : .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final background = Paint()
      ..color = selected ? Colors.white : AppColors.primary;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 160, 64),
        const Radius.circular(22),
      ),
      background,
    );

    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 160, 64),
          const Radius.circular(22),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = AppColors.primary,
      );
    }

    // Pointer
    final path = Path();

    path.moveTo(72, 64);
    path.lineTo(88, 64);
    path.lineTo(80, 84);
    path.close();

    canvas.drawPath(path, background);

    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    tp.text = TextSpan(
      text: '${_emoji(category)}  $attendeeCount',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: selected ? AppColors.primary : Colors.white,
      ),
    );

    tp.layout();

    tp.paint(canvas, Offset(80 - tp.width / 2, 18));

    final picture = recorder.endRecording();

    final image = await picture.toImage(
      markerWidth.toInt(),
      markerHeight.toInt(),
    );

    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static String _emoji(String category) {
    switch (category) {
      case 'Fitness & Sport':
        return '💪';

      case 'Family':
        return '👨‍👩‍👧';

      case 'Pets':
        return '🐶';

      case 'Hobbies':
        return '🎨';

      case 'Social':
        return '🎉';

      case 'Volunteering':
        return '❤️';

      case 'Learning':
        return '📚';

      case 'Local Deals':
        return '🏷️';

      default:
        return '📍';
    }
  }
}
