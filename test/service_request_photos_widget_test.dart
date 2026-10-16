import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/widgets/service_request_photos.dart';

void main() {
  const urls = [
    'https://example.com/one.jpg',
    'https://example.com/two.jpg',
    'https://example.com/three.jpg',
  ];

  testWidgets('photo strip hides itself when there are no photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ServiceRequestPhotoStrip(imageUrls: [])),
      ),
    );

    expect(
      find.byKey(const ValueKey('service-request-photo-strip')),
      findsNothing,
    );
  });

  testWidgets('photo strip displays request photos and opens viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ServiceRequestPhotoStrip(imageUrls: urls)),
      ),
    );

    expect(
      find.byKey(const ValueKey('service-request-photo-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('service-request-photo-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('service-request-photo-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('service-request-photo-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('service-request-photo-0')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('business preview shows first photo and remaining count', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ServiceRequestPhotoPreview(imageUrls: urls)),
      ),
    );

    expect(
      find.byKey(const ValueKey('service-request-photo-preview')),
      findsOneWidget,
    );
    expect(find.text('+2'), findsOneWidget);
  });
}
