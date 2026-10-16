import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:locallink_flutter/widgets/opportunity_feed.dart';
import 'package:locallink_flutter/services/organisation_discovery_service.dart';
import 'package:locallink_flutter/services/home_feed_rules.dart';
import 'package:locallink_flutter/services/local_discovery_filters.dart';

const organisation = <String, dynamic>{
  'name': 'Men Walking and Talking',
  'category': 'Wellbeing & Support',
  'location': 'Burntwood Rugby Club, Chasetown, Burntwood, UK',
  'publicLocation': 'Burntwood',
  'isActive': true,
  'createdByModerator': true,
  'claimStatus': 'unclaimed',
  'listingOwnershipStatus': 'unclaimed',
  'latitude': 52.6719945,
  'longitude': -1.9428779,
};
List<OrganisationDiscoveryCandidate> nearby(
  Map<String, dynamic> data, {
  double? latitude = 52.6719945,
  double? longitude = -1.9428779,
  double radius = 15,
  String query = '',
}) => OrganisationDiscoveryService.nearbyCandidates(
  records: [OrganisationDiscoveryRecord(id: 'reported-org', data: data)],
  userLatitude: latitude,
  userLongitude: longitude,
  radiusMiles: radius,
  query: query,
);

void main() {
  final position = Position(
    latitude: 52.6719945,
    longitude: -1.9428779,
    timestamp: DateTime(2026),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );
  const record = OrganisationDiscoveryRecord(
    id: 'reported-org',
    data: organisation,
  );
  test(
    'actual Home assembler displays standalone organisation without activities',
    () {
      final items = buildHomeOrganisationDiscoveryForTest(
        organisations: [record],
        position: position,
      );
      expect(items.single.type, HomeFeedContentType.organisation);
      expect(items.single.item['id'], 'reported-org');
    },
  );
  test(
    'actual Home assembler gives public recurring activities separate feed items',
    () {
      final activity = _OrganisationDoc('walk', {
        'title': 'Weekly walk',
        'isActive': true,
        'isRecurring': true,
        'organisationId': 'reported-org',
        'activityAudienceScope': 'everyone',
        'isPubliclyDiscoverable': true,
        'latitude': 52.6719945,
        'longitude': -1.9428779,
      });
      final items = buildHomeOrganisationDiscoveryForTest(
        organisations: [record],
        position: position,
        opportunities: [activity],
      );
      expect(
        items.map((item) => item.type),
        containsAll([
          HomeFeedContentType.activity,
          HomeFeedContentType.organisation,
        ]),
      );
      expect(
        items.map((item) => item.item['id']),
        containsAll(['walk', 'reported-org']),
      );
      final activities = buildHomeOrganisationDiscoveryForTest(
        organisations: [record],
        position: position,
        opportunities: [activity],
        category: HomeDiscoveryCategory.activities,
      );
      expect(activities.single.item['id'], 'walk');
    },
  );
  test(
    'reported restricted activity cannot suppress its independently public organisation',
    () {
      final restricted = _OrganisationDoc('restricted-walk', {
        'isActive': true,
        'isRecurring': true,
        'organisationId': 'reported-org',
        'discoveryVisibility': 'restricted',
        'latitude': 52.6719945,
        'longitude': -1.9428779,
      });
      final items = buildHomeOrganisationDiscoveryForTest(
        organisations: [record],
        position: position,
        opportunities: [restricted],
      );
      expect(items.single.item['id'], 'reported-org');
      expect(items.single.type, HomeFeedContentType.organisation);
    },
  );
  test(
    'organisation stream reads active parent records independently of activities',
    () async {
      final store = _OrganisationStore([
        _OrganisationDoc('public', organisation),
        _OrganisationDoc('private', {...organisation, 'visibility': 'private'}),
        _OrganisationDoc('inactive', {...organisation, 'isActive': false}),
      ]);
      final records =
          await OrganisationDiscoveryService.watchActiveOrganisations(
            firestore: store,
          ).first;
      expect(store.queryFilteredActive, isTrue);
      expect(records.map((item) => item.id), ['public', 'private']);
      final visible = OrganisationDiscoveryService.nearbyCandidates(
        records: records,
        userLatitude: 52.6719945,
        userLongitude: -1.9428779,
      );
      expect(visible.map((item) => item.record.id), ['public']);
    },
  );
  test(
    'reported unclaimed admin organisation appears without activity data',
    () {
      final result = nearby(organisation);
      expect(result.single.record.id, 'reported-org');
      expect(result.single.distanceMiles, closeTo(0, 0.001));
      expect(result.single.record.data.containsKey('activities'), isFalse);
    },
  );
  test(
    'explicitly public unclaimed organisation needs no claim, service or booking',
    () {
      final data = {
        ...organisation,
        'createdByModerator': false,
        'visibility': 'public',
      };
      expect(nearby(data), hasLength(1));
    },
  );
  test('existing self-service public creation remains discoverable', () {
    expect(
      nearby({
        ...organisation,
        'createdByModerator': false,
        'selfServiceCreated': true,
      }),
      hasLength(1),
    );
  });
  test(
    'private, inactive and moderated records never appear, even for an admin',
    () {
      for (final blocker in <Map<String, dynamic>>[
        {'isActive': false},
        {'isActive': null},
        {'visibility': 'private'},
        {'visibility': 'members_only'},
        {'discoveryVisibility': 'restricted'},
        {'isPrivate': true},
        {'private': true},
        {'isPublic': false},
        {'isPubliclyDiscoverable': false},
        {'isHidden': true},
        {'isArchived': true},
        {'moderationStatus': 'removed'},
        {'visibility': 'unknown'},
        {'visibility': null},
        {'isPrivate': 'false'},
      ]) {
        expect(
          nearby({...organisation, ...blocker}),
          isEmpty,
          reason: '$blocker',
        );
      }
    },
  );
  test(
    'ambiguous legacy organisation without established public origin stays hidden',
    () {
      expect(nearby({...organisation, 'createdByModerator': false}), isEmpty);
    },
  );
  test('coordinates and user location are required; radius is enforced', () {
    expect(nearby(organisation, latitude: null), isEmpty);
    expect(nearby(organisation, longitude: null), isEmpty);
    for (final coords in <Map<String, dynamic>>[
      {'latitude': null},
      {'longitude': null},
      {'latitude': double.nan},
      {'longitude': double.infinity},
      {'latitude': 91},
      {'longitude': -181},
      {'latitude': 0, 'longitude': 0},
      {'latitude': 51.5, 'longitude': -0.1},
    ]) {
      expect(nearby({...organisation, ...coords}), isEmpty, reason: '$coords');
    }
    expect(nearby({...organisation, 'latitude': 52.7}, radius: 1), isEmpty);
    expect(
      nearby({...organisation, 'latitude': 52.7}, radius: 5),
      hasLength(1),
    );
  });
  test('search matches organisation name, category and location', () {
    expect(nearby(organisation, query: 'men walking'), hasLength(1));
    expect(nearby(organisation, query: 'wellbeing'), hasLength(1));
    expect(nearby(organisation, query: 'burntwood'), hasLength(1));
    expect(nearby(organisation, query: 'unrelated'), isEmpty);
  });
  test('organisation has no activity date restriction', () {
    expect(
      nearby({
        ...organisation,
        'activityCount': 0,
        'eventDate': DateTime(2000),
      }),
      hasLength(1),
    );
  });
  test(
    'public recurring activity stays separately eligible; restricted activity stays hidden',
    () {
      final publicActivity = <String, dynamic>{
        'title': 'Weekly walk',
        'organisationId': 'reported-org',
        'isActive': true,
        'isRecurring': true,
        'activityAudienceScope': 'everyone',
        'isPubliclyDiscoverable': true,
      };
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable(
          publicActivity,
          now: DateTime(2026, 10, 13),
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          ...publicActivity,
          'activityAudienceScope': 'organisation',
          'isPubliclyDiscoverable': false,
        }, now: DateTime(2026, 10, 13)),
        isFalse,
      );
      expect(nearby(organisation), hasLength(1));
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.activities,
          HomeFeedContentType.activity,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.organisations,
          HomeFeedContentType.organisation,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.activities,
          HomeFeedContentType.organisation,
        ),
        isFalse,
      );
    },
  );
  test(
    'organisation participates in existing balanced round-robin and radius policy',
    () {
      final input = [
        for (var n = 0; n < 4; n++)
          HomeFeedCandidate(
            item: 'org$n',
            type: HomeFeedContentType.organisation,
            distanceMiles: 1,
          ),
        const HomeFeedCandidate(
          item: 'business',
          type: HomeFeedContentType.standaloneBusiness,
          distanceMiles: 1,
        ),
        const HomeFeedCandidate(
          item: 'activity',
          type: HomeFeedContentType.activity,
          distanceMiles: 1,
        ),
        const HomeFeedCandidate(
          item: 'help',
          type: HomeFeedContentType.communityHelp,
          distanceMiles: 1,
        ),
        const HomeFeedCandidate(
          item: 'service',
          type: HomeFeedContentType.serviceBusiness,
          distanceMiles: 1,
        ),
      ];
      final mixed = HomeFeedRules.mix(
        HomeFeedRules.applyProgressiveRadius(input),
      );
      expect(mixed.take(5).map((item) => item.type).toSet(), hasLength(5));
      expect(mixed, hasLength(8));
    },
  );
}

// Test-only SDK snapshots; the SDK marks its implementations sealed.
// ignore: subtype_of_sealed_class
class _OrganisationDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _OrganisationDoc(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
}

class _OrganisationSnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _OrganisationSnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _OrganisationStore extends Fake implements FirebaseFirestore {
  _OrganisationStore(this.docs);
  final List<_OrganisationDoc> docs;
  bool queryFilteredActive = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, 'organisations'); // No opportunities/activities dependency.
    return _OrganisationCollection(this);
  }
}

// Test-only query double verifies the exact parent query without Firebase initialization.
// ignore: subtype_of_sealed_class
class _OrganisationCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _OrganisationCollection(this.store);
  final _OrganisationStore store;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      expect(invocation.positionalArguments.single, 'isActive');
      expect(invocation.namedArguments[#isEqualTo], isTrue);
      store.queryFilteredActive = true;
      return this;
    }
    if (invocation.memberName == #snapshots) {
      return Stream.value(
        _OrganisationSnapshot(
          store.docs.where((doc) => doc.value['isActive'] == true).toList(),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}
