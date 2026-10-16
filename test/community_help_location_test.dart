import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/community_help_location.dart';

void main() {
  group('CommunityHelpLocation.publicLabel', () {
    test('prefers the report location over a moderator-selected area', () {
      expect(
        CommunityHelpLocation.publicLabel({
          'location': 'Chasewater Country Park, Pool Road',
          'publicLocation': 'Burntwood',
          'area': 'Burntwood',
          'communityAdded': true,
        }),
        'Chasewater Country Park, Pool Road',
      );
    });

    test('prefers an explicit last-seen location', () {
      expect(
        CommunityHelpLocation.publicLabel({
          'lastSeenLocation': 'Near the west car park',
          'location': 'Chasewater Country Park',
          'area': 'Burntwood',
        }),
        'Near the west car park',
      );
    });

    test('uses readable address data before a general area', () {
      expect(
        CommunityHelpLocation.publicLabel({
          'address': 'High Street, Lichfield',
          'area': 'Lichfield',
          'createdByModerator': true,
        }),
        'High Street, Lichfield',
      );
    });

    test('preserves a member report public location for privacy', () {
      expect(
        CommunityHelpLocation.publicLabel({
          'location': '12 Example Street, Burntwood',
          'publicLocation': 'Burntwood',
        }),
        'Burntwood',
      );
    });

    test('falls back to the general area when nothing specific exists', () {
      expect(
        CommunityHelpLocation.publicLabel({'area': 'Burntwood'}),
        'Burntwood',
      );
    });

    test('ignores blank values', () {
      expect(
        CommunityHelpLocation.publicLabel({
          'location': '  ',
          'publicLocation': 'Chasetown',
          'area': 'Burntwood',
        }),
        'Chasetown',
      );
    });
  });
  test(
    'selected public area excludes street numbers, full postcode and property identifiers',
    () {
      expect(
        CommunityHelpLocation.areaFromComponents([
          {
            'long_name': '11',
            'types': ['street_number'],
          },
          {
            'long_name': 'Victoria Road',
            'types': ['route'],
          },
          {
            'long_name': 'Dundee',
            'types': ['postal_town'],
          },
        ]),
        'Dundee',
      );
      expect(
        CommunityHelpLocation.safeInputLabel(
          '11 Victoria Road, Dundee DD1 1AA',
        ),
        'Victoria Road, Dundee DD1',
      );
      expect(CommunityHelpLocation.areaFromComponents([]), 'Selected area');
    },
  );
  test(
    'Home and maps use a complete approximate pair without mixing stale coordinates',
    () {
      expect(
        CommunityHelpLocation.coordinates({
          'approxLatitude': 56.4621,
          'approxLongitude': -2.9712,
          'latitude': 52.67,
          'longitude': -1.92,
        }),
        (latitude: 56.4621, longitude: -2.9712),
      );
      expect(
        CommunityHelpLocation.coordinates({
          'approxLatitude': 56.46,
          'longitude': -1.92,
        }),
        isNull,
      );
      expect(
        CommunityHelpLocation.coordinates({
          'latitude': 56.4621,
          'longitude': -2.9712,
        }),
        (latitude: 56.46, longitude: -2.97),
      );
    },
  );
}
