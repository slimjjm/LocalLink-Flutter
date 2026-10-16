import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/public_explore_preview.dart';

void main() {
  group('PublicExplorePreview', () {
    test('builds exact public paths for shared preview types', () {
      expect(
        const PublicExplorePreview(
          type: 'communityHelp',
          id: 'help-1',
          label: 'Missing dog',
          title: 'Milo',
        ).publicUri?.path,
        '/community-help/help-1',
      );
      expect(
        const PublicExplorePreview(
          type: 'opportunity',
          id: 'opp-1',
          label: 'Football',
          title: 'Football tonight',
        ).publicUri?.path,
        '/opportunities/opp-1',
      );
      expect(
        const PublicExplorePreview(
          type: 'availability',
          id: 'slot-1',
          label: 'Available time',
          title: 'Cleaner available',
        ).publicUri?.path,
        '/availability/slot-1',
      );
      expect(
        const PublicExplorePreview(
          type: 'business',
          id: 'business-1',
          label: 'Cleaner',
          title: 'CG Elite Cleaning',
        ).publicUri?.path,
        '/businesses/business-1',
      );
      expect(
        const PublicExplorePreview(
          type: 'service',
          parentId: 'business-1',
          id: 'service-1',
          label: 'Service',
          title: 'Weekly clean',
        ).publicUri?.path,
        '/services/business-1/service-1',
      );
    });

    test('does not create service paths without a business id', () {
      expect(
        const PublicExplorePreview(
          type: 'service',
          id: 'service-1',
          label: 'Service',
          title: 'Weekly clean',
        ).publicUri,
        isNull,
      );
    });
  });

  group('PublicExploreRoute', () {
    test('matches bare explore route', () {
      final route = PublicExploreRoute.fromUri(Uri.parse('/explore'));

      expect(route, isNotNull);
      expect(route!.area, isEmpty);
    });

    test('extracts area route segment', () {
      final route = PublicExploreRoute.fromUri(Uri.parse('/explore/Burntwood'));

      expect(route, isNotNull);
      expect(route!.area, 'Burntwood');
    });

    test('ignores non explore routes', () {
      expect(
        PublicExploreRoute.fromUri(Uri.parse('/opportunities/abc')),
        isNull,
      );
    });
  });
}
