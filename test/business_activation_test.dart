import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/business_activation_policy.dart';
import 'package:locallink_flutter/services/business_dashboard_service.dart';
import 'package:locallink_flutter/models/business_dashboard_model.dart';
import 'package:locallink_flutter/services/business_discovery_service.dart';
import 'package:locallink_flutter/services/notification_router.dart';
import 'package:locallink_flutter/widgets/business_contact_actions.dart';

Map<String, dynamic> listing([Map<String, dynamic> overrides = const {}]) => {
  'ownerId': 'owner',
  'isClaimed': true,
  'isActive': true,
  'category': 'Hair Salon',
  ...overrides,
};
BusinessDashboardModel model({
  bool services = false,
  bool availability = false,
  bool direct = false,
  bool accepting = true,
  bool payment = false,
  bool staff = false,
  bool contact = false,
  bool claimed = true,
  bool live = true,
  bool restricted = false,
  String category = 'Hair Salon',
}) => BusinessDashboardModel(
  todayBookings: 0,
  upcomingBookings: 0,
  upcomingRevenue: 0,
  unreadMessages: 0,
  newEnquiries: 0,
  activeStaff: staff ? 1 : 0,
  liveAvailability: availability ? 1 : 0,
  scheduledAvailability: 0,
  pendingApprovalBookings: 0,
  expiredAvailabilityToday: 0,
  freeStaffSlots: 1,
  extraStaffSlots: 0,
  stripeConnected: false,
  restrictionMode: restricted,
  hasServices: services,
  hasAvailability: availability,
  hasDirectAvailability: direct,
  acceptingEnquiries: accepting,
  hasStaff: staff,
  hasPhotos: false,
  profileComplete: false,
  listingLive: live,
  hasClaimedOwner: claimed,
  hasContactOptions: contact,
  hasPaymentMethod: payment,
  category: category,
);

void main() {
  test(
    'contact visibility preserves existing discovery blocks and legacy active defaults',
    () {
      for (final patch in [
        {'isPrivate': true},
        {'isHidden': true},
        {'isDeleted': true},
        {'visibility': 'members_only'},
        {'status': 'archived'},
      ]) {
        expect(
          BusinessActivationPolicy.contactLinks(
            listing({...patch, 'email': 'hello@example.com'}),
          ),
          isEmpty,
        );
      }
      final legacy = listing({'email': 'hello@example.com'})
        ..remove('isActive');
      expect(BusinessActivationPolicy.listingLive(legacy), true);
      expect(BusinessActivationPolicy.contactLinks(legacy).length, 1);
      expect(
        BusinessActivationPolicy.contactLinks(listing({'phone': '--------'})),
        isEmpty,
      );
      expect(
        BusinessActivationPolicy.contactLinks(
          listing({'phone': '+44 (0)1234 567890'}),
        )['Call business']!.path,
        '+441234567890',
      );
    },
  );

  test(
    'readiness requires usable time for an active service, with direct and staff routes',
    () {
      final now = DateTime(2026, 10, 9, 12);
      final services = [
        {'id': 's', 'isActive': true, 'price': 2000, 'durationMinutes': 60},
      ];
      final staff = [
        {
          'id': 'p',
          'isActive': true,
          'serviceIds': ['s'],
        },
      ];
      final first = {
        'staffId': 'p',
        'isBooked': false,
        'startTime': now.add(const Duration(hours: 1)),
        'endTime': now.add(const Duration(minutes: 90)),
      };
      final second = {
        'staffId': 'p',
        'isBooked': false,
        'startTime': now.add(const Duration(minutes: 90)),
        'endTime': now.add(const Duration(hours: 2)),
      };
      bool ready({
        List<Map<String, dynamic>> slots = const [],
        List<Map<String, dynamic>> posts = const [],
        List<Map<String, dynamic>>? people,
      }) => BusinessActivationPolicy.hasBookingOptions(
        services: services,
        staff: people ?? staff,
        slots: slots,
        posts: posts,
        now: now,
      );
      expect(ready(slots: [first]), false);
      expect(ready(slots: [first, second]), true);
      expect(
        ready(
          slots: [
            first,
            {...second, 'isBooked': true},
          ],
        ),
        false,
      );
      expect(
        ready(
          slots: [
            first,
            {...second, 'lockExpiresAt': now.add(const Duration(hours: 3))},
          ],
        ),
        false,
      );
      expect(
        ready(
          slots: [first, second],
          people: [
            {
              'id': 'p',
              'isActive': true,
              'serviceIds': ['other'],
            },
          ],
        ),
        false,
      );
      final post = {
        'serviceId': 's',
        'isActive': true,
        'status': 'live',
        'startDateTime': now.add(const Duration(days: 1)),
      };
      expect(ready(posts: [post], people: []), true);
      expect(
        ready(
          posts: [
            {...post, 'serviceId': 'archived'},
          ],
        ),
        false,
      );
      expect(
        ready(
          posts: [
            {...post, 'status': 'expired'},
          ],
        ),
        false,
      );
      expect(
        ready(
          posts: [
            {...post, 'startDateTime': now.subtract(const Duration(days: 1))},
          ],
        ),
        false,
      );
    },
  );

  test(
    'direct availability readiness ignores commercial restrictions without staff or paid seats',
    () {
      final dashboard = model(
        services: true,
        availability: true,
        direct: true,
        payment: true,
        restricted: true,
      );
      expect(dashboard.extraStaffSlots, 0);
      expect(dashboard.hasStaff, false);
      expect(dashboard.stripeConnected, false);
      expect(dashboard.canBook, true);
      expect(dashboard.healthTitle, 'Customers can make bookings');
      expect(dashboard.nextStep, isNot(contains('subscription')));
    },
  );
  test('legacy-only readiness keeps existing restriction behaviour', () {
    expect(
      model(
        services: true,
        availability: true,
        payment: true,
        restricted: true,
      ).canBook,
      false,
    );
    expect(
      model(services: true, availability: true, payment: true).canBook,
      true,
    );
  });
  test(
    'direct readiness preserves owner, live listing, service, availability, payment and enquiry requirements',
    () {
      for (final dashboard in [
        model(
          services: true,
          availability: true,
          direct: true,
          payment: true,
          claimed: false,
        ),
        model(
          services: true,
          availability: true,
          direct: true,
          payment: true,
          live: false,
        ),
        model(availability: true, direct: true, payment: true),
        model(services: true, direct: true, payment: true),
        model(services: true, availability: true, direct: true),
        model(
          services: true,
          availability: true,
          direct: true,
          payment: true,
          accepting: false,
        ),
      ]) {
        expect(dashboard.canBook, false);
      }
    },
  );
  test(
    'direct readiness recognises usable offered capacity and rejects exhausted, archived, expired or unrelated posts',
    () {
      final now = DateTime(2030, 1, 1);
      final service = {'id': 'service', 'isActive': true, 'price': 1000};
      final post = <String, dynamic>{
        'serviceId': 'service',
        'isActive': true,
        'status': 'live',
        'remainingCapacity': 1,
        'endDateTime': now.add(const Duration(hours: 2)),
      };
      bool usable(Map<String, dynamic> value) =>
          BusinessDashboardService.hasUsableDirectAvailability(
            services: [service],
            posts: [value],
            now: now,
          );
      expect(usable(post), true);
      expect(usable({...post, 'remainingCapacity': '1'}), true);
      for (final value in [
        {...post, 'remainingCapacity': 0},
        {...post, 'remainingCapacity': 'invalid'},
        {...post, 'archived': true},
        {...post, 'endDateTime': now.subtract(const Duration(minutes: 1))},
        {...post, 'serviceId': 'foreign-service'},
        {...post, 'isActive': false},
      ]) {
        expect(usable(value), false);
      }
      expect(
        BusinessDashboardService.hasUsableDirectAvailability(
          services: [
            {...service, 'isActive': false},
          ],
          posts: [post],
          now: now,
        ),
        false,
      );
    },
  );
  test('published business remains discoverable without services', () {
    expect(BusinessDiscoveryService.isPubliclyDiscoverable(listing()), true);
  });
  test(
    'readiness distinguishes listing, enquiry and bookings without Stripe/photos',
    () {
      expect(model().healthTitle, 'Listing is live');
      expect(model(contact: true).healthTitle, 'Customers can make enquiries');
      expect(model(services: true).canEnquire, true);
      expect(
        model(
          services: true,
          availability: true,
          payment: true,
          staff: true,
        ).canBook,
        true,
      );
      expect(
        model(
          services: true,
          availability: true,
          payment: true,
          staff: true,
          restricted: true,
        ).canBook,
        false,
      );
      expect(model(contact: true, claimed: false).canEnquire, false);
      expect(model(contact: true, live: false).canEnquire, false);
    },
  );
  test(
    'appointment guidance differs from trades and listing-only businesses',
    () {
      expect(model().suggestsFirstService, true);
      expect(model(category: 'Gardener').nextStep, contains('quote'));
      for (final category in ['Café', 'Shop', 'Unknown']) {
        expect(model(category: category).suggestsFirstService, false);
        expect(model(category: category).nextStep, contains('only if'));
      }
    },
  );
  test(
    'unclaimed listings and unsafe contacts never expose contact actions',
    () {
      expect(
        BusinessActivationPolicy.contactLinks(
          listing({'isClaimed': false, 'phone': '01234567890'}),
        ),
        isEmpty,
      );
      expect(
        BusinessActivationPolicy.contactLinks(
          listing({'ownerId': '', 'email': 'a@example.com'}),
        ),
        isEmpty,
      );
      expect(
        BusinessActivationPolicy.contactLinks(
          listing({
            'website': 'javascript:alert(1)',
            'email': 'a@example.com?bcc=other',
            'phone': 'abc',
          }),
        ),
        isEmpty,
      );
      expect(
        BusinessActivationPolicy.contactLinks(
          listing({'isActive': false, 'website': 'https://example.com'}),
        ),
        isEmpty,
      );
    },
  );
  test('valid contacts use existing details, never a moderator profile', () {
    final links = BusinessActivationPolicy.contactLinks(
      listing({
        'phone': '+44 (0)1234 567890',
        'email': 'hello@example.com',
        'website': 'https://example.com',
      }),
    );
    expect(links.length, 3);
    expect(links['Call business']!.scheme, 'tel');
    expect(links['Email business']!.path, 'hello@example.com');
  });
  test(
    'setup notification has explicit route; missing, unsupported and malformed routes safely fall back',
    () {
      final route = NotificationRouter.resolve({
        'type': 'business_service_setup',
        'businessId': 'b',
      });
      expect(route.kind, NotificationRouteKind.businessServiceSetup);
      expect(route.arguments['businessId'], 'b');
      expect(
        NotificationRouter.resolve({'type': 'business_service_setup'}).kind,
        NotificationRouteKind.notifications,
      );
      expect(
        NotificationRouter.resolve({
          'type': 'business_service_setup',
          'businessId': 'b/services/s',
        }).kind,
        NotificationRouteKind.notifications,
      );
      expect(
        NotificationRouter.resolve({'type': 'unsupported_setup'}).kind,
        NotificationRouteKind.home,
      );
    },
  );
  testWidgets('unsupported external route shows usable copyable details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessContactActions(
            businessData: listing({'email': 'hello@example.com'}),
            launchContact: (_) async => false,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Email business'));
    await tester.pumpAndSettle();
    expect(find.text('Contact details'), findsOneWidget);
    expect(find.text('hello@example.com'), findsOneWidget);
  });
  testWidgets(
    'listing without contact has honest empty state and no fake enquiry button',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BusinessContactActions(businessData: listing())),
        ),
      );
      expect(
        find.textContaining('Contact details are not available'),
        findsOneWidget,
      );
      expect(find.byType(OutlinedButton), findsNothing);
    },
  );
}
