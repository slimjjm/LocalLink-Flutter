import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/organisation.dart';

void main() {
  test('organisation model reads moderator seeded parent fields', () {
    final organisation = Organisation.fromMap('org-1', {
      'name': 'Burntwood Rugby Club',
      'description': 'Community rugby for juniors and adults.',
      'category': 'Fitness & Sport',
      'subcategories': ['Rugby', 'Junior sport'],
      'area': 'Burntwood',
      'publicLocation': 'Burntwood',
      'location': 'Burntwood Rugby Club',
      'phone': '01234 567890',
      'email': 'club@example.com',
      'website': 'https://example.com',
      'imageUrl': 'https://example.com/logo.jpg',
      'ownerId': '',
      'adminUserIds': [],
      'createdByModerator': true,
      'claimStatus': 'unclaimed',
      'listingOwnershipStatus': 'unclaimed',
      'isActive': true,
      'latitude': 52.6801,
      'longitude': -1.927,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });

    expect(organisation.id, 'org-1');
    expect(organisation.name, 'Burntwood Rugby Club');
    expect(organisation.category, 'Fitness & Sport');
    expect(organisation.subcategories, ['Rugby', 'Junior sport']);
    expect(organisation.area, 'Burntwood');
    expect(organisation.publicLocation, 'Burntwood');
    expect(organisation.createdByModerator, isTrue);
    expect(organisation.claimStatus, 'unclaimed');
    expect(organisation.latitude, 52.6801);
    expect(organisation.isClaimed, isFalse);
    expect(organisation.isManagedBy('organiser-1'), isFalse);
  });

  test(
    'organisation ownership helpers recognise approved owner and admins',
    () {
      final organisation = Organisation.fromMap('org-claimed', {
        'name': 'Burntwood Rugby Club',
        'ownerId': 'owner-1',
        'adminUserIds': ['admin-1', 'admin-2'],
        'claimStatus': 'approved',
        'listingOwnershipStatus': 'claimed',
      });

      expect(organisation.isClaimed, isTrue);
      expect(organisation.isManagedBy('owner-1'), isTrue);
      expect(organisation.isManagedBy('admin-2'), isTrue);
      expect(organisation.isManagedBy('other-user'), isFalse);
      expect(organisation.isManagedBy(null), isFalse);
    },
  );

  test('linked activity remains an opportunity with organisation context', () {
    final activityData = {
      'title': 'U8 Rugby Training',
      'category': 'Fitness & Sport',
      'activityType': 'Rugby',
      'ageGroup': 'Under 8',
      'scheduleText': 'Wednesday 18:00',
      'organisationId': 'org-1',
      'organisationName': 'Burntwood Rugby Club',
      'organisationCategory': 'Fitness & Sport',
      'organisationSubcategories': ['Rugby'],
      'isRecurring': true,
      'repeatType': 'weekly',
      'isActive': true,
    };

    expect(activityData['organisationId'], 'org-1');
    expect(activityData['organisationName'], 'Burntwood Rugby Club');
    expect(activityData['isRecurring'], isTrue);
    expect(activityData['repeatType'], 'weekly');
  });
}
