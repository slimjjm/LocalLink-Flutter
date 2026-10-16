import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/local_discovery_filters.dart';
import 'package:locallink_flutter/widgets/opportunity_map_view.dart';
import 'package:locallink_flutter/screens/organisation_detail_screen.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);
  Map<String, dynamic> activity(
    DateTime date, {
    String series = 'walk-series',
    bool recurring = true,
  }) => {
    'title': 'Monday walk',
    'organisationId': 'org',
    'isActive': true,
    'activityAudienceScope': 'everyone',
    'isPubliclyDiscoverable': true,
    'discoveryVisibility': 'public',
    'isRecurring': recurring,
    'repeatType': 'weekly',
    'seriesId': series,
    'eventDate': Timestamp.fromDate(date),
    'eventTime': '18:30',
    'scheduleText': '20/7/2026 18:30 - 19:30',
  };
  test(
    'DST-generated upcoming occurrences remain eligible in feeds map and profile',
    () {
      for (final iso in ['2026-10-26T18:30:00Z', '2026-03-30T17:30:00Z']) {
        final date = DateTime.parse(iso);
        final before = date.subtract(const Duration(hours: 1));
        final data = {
          ...activity(date),
          'recurrenceTimeZone': 'Europe/London',
          'endTime': '19:30',
        };
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable(data, now: before),
          isTrue,
        );
        expect(isPublicMapActivity(data, now: before), isTrue);
        expect(
          selectUpcomingOrganisationActivityDocs([
            _Doc('dst', data),
          ], now: before).single.id,
          'dst',
        );
        expect(
          organisationActivityRecurrenceLabel(data),
          'Every Monday · 18:30 - 19:30',
        );
        final restricted = {
          ...data,
          'activityAudienceScope': 'organisation',
          'isPubliclyDiscoverable': false,
          'discoveryVisibility': 'restricted',
        };
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable(restricted, now: before),
          isFalse,
        );
        expect(isPublicMapActivity(restricted, now: before), isFalse);
        expect(
          selectUpcomingOrganisationActivityDocs([
            _Doc('private', restricted),
          ], now: before),
          isEmpty,
        );
      }
    },
  );
  test(
    'future occurrence survives an active historical seed and series deduplication',
    () {
      final old = _Doc('seed', activity(DateTime(2026, 7, 20)));
      final next = _Doc('next', activity(DateTime(2026, 10, 19)));
      final later = _Doc('later', activity(DateTime(2026, 10, 26)));
      final selected = selectUpcomingOrganisationActivityDocs([
        old,
        later,
        next,
      ], now: now);
      expect(selected.map((item) => item.id), ['next']);
    },
  );
  test(
    'recurring label uses actual weekday/time rather than copied historical schedule date',
    () {
      final text = organisationActivityRecurrenceLabel(
        activity(DateTime(2026, 10, 19)),
      );
      expect(text, 'Every Monday · 18:30');
      expect(text, isNot(contains('20/7/2026')));
    },
  );
  test('structured weekly label preserves the saved evening end time', () {
    expect(
      organisationActivityRecurrenceLabel({
        ...activity(DateTime(2026, 10, 19)),
        'endTime': '19:30',
      }),
      'Every Monday · 18:30 - 19:30',
    );
  });
  test(
    'future public setup activity immediately appears even if unclaimed',
    () {
      final data = {
        ...activity(DateTime(2026, 10, 19)),
        'createdByModerator': true,
        'claimStatus': 'unclaimed',
        'listingOwnershipStatus': 'unclaimed',
      };
      expect(
        selectUpcomingOrganisationActivityDocs([
          _Doc('new', data),
        ], now: now).single.id,
        'new',
      );
    },
  );
  test(
    'restricted, inactive, moderated and expired activities cannot enter public profile',
    () {
      final base = activity(DateTime(2026, 10, 19));
      for (final override in <Map<String, dynamic>>[
        {
          'activityAudienceScope': 'organisation',
          'isPubliclyDiscoverable': false,
        },
        {'visibility': 'private'},
        {'isActive': false},
        {'moderationStatus': 'removed'},
        {'eventDate': Timestamp.fromDate(DateTime(2026, 10, 12))},
      ]) {
        expect(
          selectUpcomingOrganisationActivityDocs([
            _Doc('blocked', {...base, ...override}),
          ], now: now),
          isEmpty,
          reason: '$override',
        );
      }
    },
  );
  test(
    'one-off activities stay separate and date-only activities remain valid today',
    () {
      final docs = [
        _Doc('today', activity(DateTime(2026, 10, 13), recurring: false)),
        _Doc('future', activity(DateTime(2026, 10, 19), recurring: false)),
      ];
      expect(
        selectUpcomingOrganisationActivityDocs(
          docs,
          now: now,
        ).map((item) => item.id),
        ['today', 'future'],
      );
    },
  );
}

// Test-only SDK snapshot stand-in, consistent with existing repository tests.
// ignore: subtype_of_sealed_class
class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
}
