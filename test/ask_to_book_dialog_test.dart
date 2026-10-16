import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:locallink_flutter/screens/availability_detail_screen.dart';

void main() {
  testWidgets('Time Available detail foregrounds the appointment', (
    tester,
  ) async {
    final appointmentStart = _futureAppointmentDate();
    final appointmentEnd = appointmentStart.add(const Duration(hours: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: AvailabilityDetailScreen(
          postId: 'availability-1',
          availabilityData: {
            'businessId': 'business-1',
            'serviceId': 'service-1',
            'serviceName': 'Groom',
            'serviceDetails': 'A calm tidy-up for local pets.',
            'type': 'exact',
            'startDateTime': Timestamp.fromDate(appointmentStart),
            'endDateTime': Timestamp.fromDate(appointmentEnd),
            'durationMinutes': 45,
            'price': 100,
          },
          businessData: {
            'businessName': 'test 1',
            'publicLocation': 'Burntwood',
            'isClaimed': true,
            'paymentMethods': ['cash'],
          },
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Groom'), findsOneWidget);
    expect(find.text('test 1'), findsOneWidget);
    expect(find.text(_dateLabel(appointmentStart)), findsOneWidget);
    expect(find.textContaining('6:51'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('£1.00'), findsOneWidget);
    expect(find.text('Choose this time'), findsOneWidget);
    expect(find.text('Trust details'), findsNothing);
  });

  testWidgets(
    'Ask to Book dialog opens and cancel returns null without submit',
    (tester) async {
      String? result = 'not-yet';
      var submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    final value = await showAskToBookDialog(context);
                    result = value;
                    if (value != null) submitCount += 1;
                  },
                  child: const Text('Ask to Book'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Ask to Book'));
      await tester.pumpAndSettle();

      expect(find.byType(AskToBookDialog), findsOneWidget);
      expect(find.text('Ask to book'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AskToBookDialog), findsNothing);
      expect(result, isNull);
      expect(submitCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ask to Book dialog sends trimmed text exactly once', (
    tester,
  ) async {
    String? result;
    var submitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final value = await showAskToBookDialog(context);
                  result = value;
                  if (value != null) submitCount += 1;
                },
                child: const Text('Ask to Book'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Ask to Book'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Friday morning please  ');

    await tester.tap(find.text('Send'));
    await tester.tap(find.text('Send'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(result, 'Friday morning please');
    expect(submitCount, 1);
    expect(find.byType(AskToBookDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ask to Book dialog can close while parent is replaced', (
    tester,
  ) async {
    var showParent = true;
    String? result = 'not-yet';

    Widget buildApp() {
      return MaterialApp(
        home: showParent
            ? Builder(
                builder: (context) {
                  return Scaffold(
                    body: ElevatedButton(
                      onPressed: () async {
                        result = await showAskToBookDialog(context);
                      },
                      child: const Text('Ask to Book'),
                    ),
                  );
                },
              )
            : const Scaffold(body: Text('Gone')),
      );
    }

    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Ask to Book'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    showParent = false;
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Gone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

DateTime _futureAppointmentDate() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    18,
    51,
  ).add(const Duration(days: 14));
}

String _dateLabel(DateTime value) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[value.weekday - 1]} ${value.day} ${months[value.month - 1]}';
}
