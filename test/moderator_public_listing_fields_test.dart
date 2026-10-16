import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/organisation.dart';
import 'package:locallink_flutter/services/activity_relationships.dart';
import 'package:locallink_flutter/services/moderator_public_listing_fields.dart';
import 'package:locallink_flutter/services/organisation_discovery_service.dart';
import 'package:locallink_flutter/services/local_discovery_filters.dart';
import 'package:locallink_flutter/widgets/opportunity_map_view.dart';

void main() {
  final parent = Organisation.fromMap('moderator-org', {
    'name': 'Men Walking and Talking',
    'category': 'Wellbeing & Support',
    'isActive': true,
    'createdByModerator': true,
    'claimStatus': 'unclaimed',
    'listingOwnershipStatus': 'unclaimed',
    'ownerId': '',
    'adminUserIds': <String>[],
    'latitude': 52.6719945,
    'longitude': -1.9428779,
  });
  final organisation = <String, dynamic>{
    'name': parent.name,
    'category': parent.category,
    'isActive': true,
    'createdBy': 'moderator',
    'createdByModerator': true,
    'listingOwnershipStatus': 'unclaimed',
    'claimStatus': 'unclaimed',
    'claimedByUserId': null,
    'claimedAt': null,
    'ownerId': '',
    'adminUserIds': <String>[],
    'latitude': parent.latitude,
    'longitude': parent.longitude,
    ...ModeratorPublicListingFields.organisation,
  };
  Map<String, dynamic> activity({bool linked = true, bool recurring = false}) =>
      {
        'title': 'Community walking activity',
        'isActive': true,
        'createdBy': 'moderator',
        'createdByModerator': true,
        'listingOwnershipStatus': 'unclaimed',
        'claimStatus': 'unclaimed',
        'claimedByUserId': null,
        'claimedAt': null,
        'organiserId': null,
        'latitude': parent.latitude,
        'longitude': parent.longitude,
        'isRecurring': recurring,
        'repeatType': recurring ? 'weekly' : 'none',
        'seriesId': 'moderator-series',
        'seriesStatus': 'active',
        ...ModeratorPublicListingFields.activity(
          organisation: linked ? parent : null,
        ),
      };
  test(
    'public organisation is explicitly public, active, unclaimed and discoverable',
    () {
      expect(organisation['visibility'], 'public');
      expect(organisation['claimStatus'], 'unclaimed');
      expect(organisation['ownerId'], '');
      expect(OrganisationDiscoveryService.isDiscoverable(organisation), isTrue);
    },
  );
  test(
    'linked and standalone public moderator activities save explicit public audience',
    () {
      for (final linked in [false, true]) {
        final payload = activity(linked: linked);
        expect(payload['activityAudienceScope'], 'everyone');
        expect(payload['isPubliclyDiscoverable'], isTrue);
        expect(payload['discoveryVisibility'], 'public');
        expect(payload['visibility'], 'public');
        expect(payload['claimStatus'], 'unclaimed');
        expect(payload.containsKey('organisationId'), linked);
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable(
            payload,
            now: DateTime(2026, 10, 13),
          ),
          isTrue,
        );
        expect(
          isPublicMapActivity(payload, now: DateTime(2026, 10, 13)),
          isTrue,
        );
      }
    },
  );
  test('recurrence adds scheduling without changing public audience', () {
    final payload = activity(recurring: true);
    expect(payload['isRecurring'], isTrue);
    expect(payload['repeatType'], 'weekly');
    expect(payload['discoveryVisibility'], 'public');
  });
  test('deliberate existing organisation-only audience remains protected', () {
    final restricted = {
      'isActive': true,
      ...ActivityRelationshipFields.build(
        organisation: parent,
        audienceScope: 'organisation',
      ),
    };
    expect(restricted['discoveryVisibility'], 'restricted');
    expect(restricted['isPubliclyDiscoverable'], isFalse);
    expect(
      LocalDiscoveryFilters.isActivityDiscoverable(
        restricted,
        now: DateTime(2026, 10, 13),
      ),
      isFalse,
    );
  });
  test(
    'contradictory public flags cannot override explicit private content',
    () {
      for (final privacy in [
        {'visibility': 'private'},
        {'isPrivate': true},
        {'isPubliclyDiscoverable': false},
      ]) {
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            ...activity(),
            ...privacy,
          }, now: DateTime(2026, 10, 13)),
          isFalse,
        );
      }
    },
  );
  test(
    'reviewed cross-language fixtures match the actual Flutter payload fields',
    () {
      final expected = jsonDecode(
        File(
          'test/fixtures/moderator_public_listing_payloads.json',
        ).readAsStringSync(),
      );
      expect(expected['organisation'], organisation);
      expect(expected['publicLinked'], activity());
      expect(expected['publicStandalone'], activity(linked: false));
      expect(expected['publicRecurring'], activity(recurring: true));
      expect(
        expected['restrictedOrganisation']['activityAudienceScope'],
        'organisation',
      );
    },
  );
  test(
    'exports actual Flutter payload fields for cross-language emulator verification',
    () {
      const output = String.fromEnvironment('MODERATOR_PAYLOAD_OUTPUT');
      if (output.isNotEmpty) {
        File(output).writeAsStringSync(
          jsonEncode({
            'organisation': organisation,
            'publicLinked': activity(),
            'publicStandalone': activity(linked: false),
            'publicRecurring': activity(recurring: true),
            'restrictedOrganisation': {
              'title': 'Members only',
              'isActive': true,
              'createdBy': 'moderator',
              'createdByModerator': true,
              'listingOwnershipStatus': 'unclaimed',
              'claimStatus': 'unclaimed',
              'claimedByUserId': null,
              'claimedAt': null,
              ...ActivityRelationshipFields.build(
                organisation: parent,
                audienceScope: 'organisation',
              ),
            },
          }),
        );
      }
    },
  );
}
