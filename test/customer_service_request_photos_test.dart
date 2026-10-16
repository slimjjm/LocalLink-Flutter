import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:locallink_flutter/screens/customer_service_request_screen.dart';

void main() {
  Future<void> pumpRequestScreen(
    WidgetTester tester, {
    required Future<XFile?> Function() picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerServiceRequestScreen(
          photoPicker: picker,
          selectedPhotoBuilder: (context, photo, index) {
            return Container(
              key: ValueKey('selected-service-request-photo-$index'),
              width: 104,
              height: 88,
              color: Colors.green,
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpEditScreen(
    WidgetTester tester, {
    Map<String, dynamic>? data,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerServiceRequestEditScreen(
          requestId: 'request-1',
          initialData:
              data ??
              {
                'category': 'Gardening',
                'title': 'Hedge trimming needed',
                'description': 'The front hedge needs cutting back.',
                'scheduleText': 'This weekend',
                'budgetText': '£50',
                'publicLocation': 'Burntwood',
                'approxLatitude': 52.681,
                'approxLongitude': -1.831,
                'imageUrls': [
                  'https://example.com/photo-1.jpg',
                  'https://example.com/photo-2.jpg',
                  'https://example.com/photo-3.jpg',
                ],
              },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapAddPhoto(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('add-service-request-photo'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('service request photos are optional', (tester) async {
    await pumpRequestScreen(tester, picker: () async => null);

    expect(find.text('Add photos (optional)'), findsOneWidget);
    expect(find.textContaining('0/3 photos selected'), findsOneWidget);
  });

  testWidgets('picker cancellation leaves photo selection empty', (
    tester,
  ) async {
    await pumpRequestScreen(tester, picker: () async => null);

    await tapAddPhoto(tester);

    expect(find.textContaining('0/3 photos selected'), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsNothing);
  });

  testWidgets('edit screen prepopulates request details and existing photos', (
    tester,
  ) async {
    await pumpEditScreen(tester);

    expect(find.text('Edit request'), findsOneWidget);
    expect(find.text('Hedge trimming needed'), findsOneWidget);
    expect(
      find.text('The front hedge needs cutting back.', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('This weekend', skipOffstage: false), findsOneWidget);
    expect(find.text('£50', skipOffstage: false), findsOneWidget);
    expect(find.text('Burntwood', skipOffstage: false), findsWidgets);
    expect(find.textContaining('3/3 photos selected'), findsOneWidget);

    final addButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('add-service-request-edit-photo')),
    );
    expect(addButton.onPressed, isNull);
  });

  testWidgets('edit screen supports legacy requests without imageUrls', (
    tester,
  ) async {
    await pumpEditScreen(
      tester,
      data: {
        'category': 'Cleaning',
        'title': 'Cleaner needed',
        'details': 'Kitchen and bathroom clean.',
        'neededBy': 'Friday',
        'publicLocation': 'Burntwood',
        'approxLatitude': 52.681,
        'approxLongitude': -1.831,
      },
    );

    expect(find.text('Cleaner needed'), findsOneWidget);
    expect(find.text('Kitchen and bathroom clean.'), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
    expect(find.textContaining('0/3 photos selected'), findsOneWidget);

    final addButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('add-service-request-edit-photo')),
    );
    expect(addButton.onPressed, isNotNull);
  });

  testWidgets(
    'removing an existing edit photo is pending and does not mutate initial data',
    (tester) async {
      final imageUrls = [
        'https://example.com/photo-1.jpg',
        'https://example.com/photo-2.jpg',
        'https://example.com/photo-3.jpg',
      ];
      await pumpEditScreen(
        tester,
        data: {
          'category': 'Gardening',
          'title': 'Hedge trimming needed',
          'description': 'The front hedge needs cutting back.',
          'scheduleText': 'This weekend',
          'publicLocation': 'Burntwood',
          'approxLatitude': 52.681,
          'approxLongitude': -1.831,
          'imageUrls': imageUrls,
        },
      );

      await tester.tap(
        find.byKey(const ValueKey('remove-edit-request-photo-0')),
      );
      await tester.pump();

      expect(find.textContaining('2/3 photos selected'), findsOneWidget);
      expect(imageUrls, hasLength(3));
      final addButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('add-service-request-edit-photo')),
      );
      expect(addButton.onPressed, isNotNull);
    },
  );
}
