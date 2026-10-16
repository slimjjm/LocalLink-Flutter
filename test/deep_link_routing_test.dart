import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/main.dart' as app;
import 'package:locallink_flutter/services/deep_link_service.dart';

void main() {
  group('LocalLink startup routes', () {
    test('turns shared-link route names into public LocalLink URLs', () {
      final uri = app.localLinkUriFromRouteName(
        '/opportunities/activity-1?from=share',
      );

      expect(uri?.scheme, 'https');
      expect(uri?.host, 'locallinkapp.co.uk');
      expect(uri?.path, '/opportunities/activity-1');
      expect(uri?.queryParameters['from'], 'share');
    });

    test('does not treat ordinary named routes as public shared links', () {
      expect(app.localLinkUriFromRouteName('/'), isNull);
      expect(app.localLinkUriFromRouteName('booking'), isNull);
    });

    test('generates a safe route for supported shared-link paths', () {
      final route = app.generateLocalLinkRoute(
        const RouteSettings(name: '/businesses/business-1'),
      );

      expect(route, isA<MaterialPageRoute>());
    });

    test('generates a fallback route for unsupported paths', () {
      final route = app.unknownLocalLinkRoute(
        const RouteSettings(name: '/not-a-local-link'),
      );

      expect(route, isA<MaterialPageRoute>());
    });
  });

  group('public deep-link declarations', () {
    final publicPaths = <String>[
      '/community-help',
      '/opportunities',
      '/availability',
      '/businesses',
      '/services',
      '/service-requests',
      '/invitations/organisation',
      '/stripe-return',
      '/stripe-refresh',
    ];

    test('Android app links include every supported public path family', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      for (final path in publicPaths) {
        expect(manifest, contains('android:pathPrefix="$path"'));
      }

      expect(manifest, contains('android:host="service-request"'));
      expect(manifest, contains('android:host="organisation-invitation"'));
    });

    test('iOS universal links include every supported public path family', () {
      final aasa = File(
        'web/.well-known/apple-app-site-association',
      ).readAsStringSync();

      for (final path in publicPaths) {
        final suffix = path.startsWith('/stripe-') ? '' : '/*';
        expect(aasa, contains('"$path$suffix"'));
      }
    });

    test('iOS native handoff allows every supported public path family', () {
      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final sceneDelegate = File(
        'ios/Runner/SceneDelegate.swift',
      ).readAsStringSync();

      for (final fileContent in [appDelegate, sceneDelegate]) {
        for (final path in publicPaths) {
          if (path.startsWith('/stripe-')) {
            expect(fileContent, contains('path == "$path"'));
          } else {
            expect(fileContent, contains('path.hasPrefix("$path/")'));
          }
        }

        expect(fileContent, contains('"service-request"'));
        expect(fileContent, contains('"organisation-invitation"'));
      }
    });

    test('Cloudflare redirects route shared links to the Flutter app', () {
      final redirects = File('web/_redirects').readAsStringSync();

      for (final path in publicPaths) {
        expect(redirects, contains('$path/*  /index.html  200'));
      }
    });
  });

  group('supported public URL parser', () {
    test('matches configured service request and invitation links', () {
      expect(
        LocalLinkDeepLinkTarget.fromUri(
          Uri.parse('https://locallinkapp.co.uk/service-requests/request-1'),
        )?.type,
        LocalLinkDeepLinkType.serviceRequest,
      );
      expect(
        LocalLinkDeepLinkTarget.fromUri(
          Uri.parse(
            'https://locallinkapp.co.uk/invitations/organisation/token-1',
          ),
        )?.type,
        LocalLinkDeepLinkType.organisationInvitation,
      );
    });
  });
}
