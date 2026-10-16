import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/address_result.dart';
import 'package:locallink_flutter/screens/create_choice_screen.dart';
import 'package:locallink_flutter/screens/create_organisation_screen.dart';
import 'package:locallink_flutter/screens/create_opportunity_screen.dart';
import 'package:locallink_flutter/screens/claim_review_screen.dart';
import 'package:locallink_flutter/services/address_search_service.dart';
import 'package:locallink_flutter/screens/customer_home_screen.dart';
import 'package:locallink_flutter/services/home_feed_rules.dart';
import 'package:locallink_flutter/services/home_category_preferences.dart';
import 'package:locallink_flutter/theme/local_link_theme.dart';
import 'package:locallink_flutter/widgets/local_link_button.dart';
import 'package:locallink_flutter/widgets/local_link_chip.dart';
import 'package:locallink_flutter/widgets/local_link_image.dart';
import 'package:locallink_flutter/widgets/local_link_sheet.dart';
import 'package:locallink_flutter/widgets/local_link_states.dart';
import 'package:locallink_flutter/widgets/opportunity_feed.dart';

void main() {
  final nearbyPreferences = _MemoryHomeCategoryPreferences();

  testWidgets('CustomerHomeScreen renders visible main Home content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Good evening'),
          homeCategoryPreferences: nearbyPreferences,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Ask LocalLink'), findsOneWidget);
    expect(find.text('What do you need locally?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ask-locallink-search-field')),
      findsOneWidget,
    );
    expect(
      find.text('Find services, activities, local groups and community help.'),
      findsNothing,
    );
    expect(find.text('Dog groomer tomorrow'), findsNothing);
    expect(find.text("What's on this weekend?"), findsNothing);
    expect(find.text('Something for the kids'), findsNothing);
    expect(find.text('Football clubs near me'), findsNothing);
    expect(find.text('Browse LocalLink'), findsNothing);
    expect(find.text('Browse LocalLink instead'), findsNothing);
    expect(find.text('Browse manually'), findsNothing);
    expect(find.text('Browse services'), findsNothing);
    expect(find.text('Explore your community'), findsOneWidget);
    expect(find.text("Explore what's nearby"), findsOneWidget);
    expect(find.text('I need a service'), findsNothing);
    expect(find.text('Create something'), findsNothing);
    expect(find.text('Report something'), findsNothing);
    expect(find.text('Grow your business'), findsNothing);
  });

  testWidgets('Home create action remains visible as a protected action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Header'),
          homeCategoryPreferences: nearbyPreferences,
        ),
      ),
    );

    await tester.tap(find.text('Activities'));
    await tester.pump();

    expect(find.text('Add an activity or event'), findsOneWidget);
    expect(find.text('Share something happening locally'), findsOneWidget);
    expect(find.text('Request a service'), findsNothing);
    expect(find.text('Offer a service'), findsNothing);
    expect(find.text('Add diary availability'), findsNothing);
    expect(find.text('Lost / found'), findsNothing);
    expect(find.text('Found property'), findsNothing);
  });

  testWidgets('Home discovery defaults to Nearby category labels', (
    tester,
  ) async {
    var selected = HomeDiscoveryCategory.nearby;

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: HomeDiscoveryCategoryTabs(
                selectedCategory: selected,
                onSelected: (category) {
                  setState(() => selected = category);
                },
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Businesses'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Community Help'), findsOneWidget);
    expect(find.text('Organisations'), findsOneWidget);

    final nearbyChip = tester.widget<LocalLinkChip>(
      find.widgetWithText(LocalLinkChip, 'Nearby'),
    );
    expect(nearbyChip.selected, isTrue);
  });

  testWidgets('tapping Home discovery category changes selection', (
    tester,
  ) async {
    var selected = HomeDiscoveryCategory.nearby;

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: HomeDiscoveryCategoryTabs(
                selectedCategory: selected,
                onSelected: (category) {
                  setState(() => selected = category);
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Activities'));
    await tester.pump();

    expect(selected, HomeDiscoveryCategory.activities);
    final activitiesChip = tester.widget<LocalLinkChip>(
      find.widgetWithText(LocalLinkChip, 'Activities'),
    );
    expect(activitiesChip.selected, isTrue);
  });

  testWidgets('horizontal swipe changes Home discovery category', (
    tester,
  ) async {
    var selected = HomeDiscoveryCategory.nearby;

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: HomeDiscoveryCategorySwipeRegion(
                selectedCategory: selected,
                onSelected: (category) {
                  setState(() => selected = category);
                },
                child: const SizedBox(
                  key: ValueKey('swipe-region'),
                  width: 300,
                  height: 140,
                  child: Text('Swipe me'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.fling(
      find.byKey(const ValueKey('swipe-region')),
      const Offset(-260, 0),
      800,
    );
    await tester.pump();

    expect(selected, HomeDiscoveryCategory.services);

    await tester.fling(
      find.byKey(const ValueKey('swipe-region')),
      const Offset(260, 0),
      800,
    );
    await tester.pump();

    expect(selected, HomeDiscoveryCategory.nearby);
  });

  testWidgets('Customer Home no longer renders standalone Featured card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Header'),
          homeCategoryPreferences: nearbyPreferences,
        ),
      ),
    );

    expect(find.text('FEATURED'), findsNothing);
  });

  test('Customer Home source no longer imports or renders FeaturedCard', () {
    final source = File(
      'lib/screens/customer_home_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("widgets/featured_card.dart")));
    expect(source, isNot(contains('FeaturedCard')));
  });

  testWidgets('Activity or event choice opens standalone activity creation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: const CreateChoiceScreen(),
      ),
    );

    await tester.tap(find.text('Activity or event'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateOpportunityScreen), findsOneWidget);
  });

  testWidgets('Group or organisation choice opens self-service creation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: const CreateChoiceScreen(),
      ),
    );

    await tester.tap(find.text('Group or organisation'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateOrganisationScreen), findsOneWidget);
  });

  testWidgets('club creation uses broad categories and neutral wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CreateOrganisationScreen(
          addressSearchService: _FakeAddressSearchService(),
        ),
      ),
    );

    expect(
      find.text('Create your club, group or organisation'),
      findsOneWidget,
    );
    expect(find.text('Sport & fitness'), findsOneWidget);
    expect(find.text('Charity & volunteering'), findsOneWidget);
    expect(find.text('Faith & community'), findsOneWidget);
    expect(find.text('Burntwood, Lichfield, Chasewater'), findsNothing);
    expect(find.textContaining('Running, rugby, Scouts'), findsNothing);

    await tester.tap(find.text('Music & dance'));
    await tester.pump();

    final selectedChip = tester.widget<LocalLinkChip>(
      find.widgetWithText(LocalLinkChip, 'Music & dance'),
    );
    expect(selectedChip.selected, isTrue);
  });

  testWidgets('club creation location uses address suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CreateOrganisationScreen(
          addressSearchService: _FakeAddressSearchService(),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Location'), 'town');
    await tester.pump();
    await tester.pump();

    expect(find.text('Community Hall, High Street'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pump();
    await tester.tap(find.text('Community Hall, High Street'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Community Hall, High Street'), findsOneWidget);
  });

  testWidgets('LocalLinkButton preserves its tap target while loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: LocalLinkButton(
              label: 'Send',
              onPressed: null,
              isLoading: true,
            ),
          ),
        ),
      ),
    );

    final buttonBox = tester.renderObject<RenderBox>(
      find.byType(LocalLinkButton),
    );
    expect(buttonBox.size.height, greaterThanOrEqualTo(44));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Community Help report actions show full labels on phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LocalLinkButton(
                  label: 'Report something lost',
                  icon: Icons.search_outlined,
                  onPressed: null,
                  expand: true,
                ),
                SizedBox(height: 12),
                LocalLinkButton(
                  label: 'Report something found',
                  icon: Icons.inventory_2_outlined,
                  onPressed: null,
                  variant: LocalLinkButtonVariant.secondary,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Report something lost'), findsOneWidget);
    expect(find.text('Report something found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Create activity uses scrollable V2 sections on phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: const CreateOpportunityScreen(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Create activity'), findsAtLeastNWidgets(1));
    expect(find.text('Activity details'), findsOneWidget);
    expect(find.text('Where it happens'), findsOneWidget);
    expect(find.text('When'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('LocalLinkChip reports selection changes', (tester) async {
    var selected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalLinkChip(
            label: 'Fitness & Sport',
            selected: selected,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fitness & Sport'));
    expect(selected, isTrue);
  });

  testWidgets('LocalLinkImage shows a fallback without a URL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LocalLinkImage(
            fallbackIcon: Icons.pets_rounded,
            semanticLabel: 'Missing pet photo',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
  });

  testWidgets('LocalLinkSheetScaffold keeps long content scrollable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalLinkSheetScaffold(
            title: 'Edit activity',
            primaryLabel: 'Save',
            onPrimaryPressed: () {},
            child: Column(
              children: List.generate(
                24,
                (index) => LocalLinkEmptyState(
                  icon: Icons.event_rounded,
                  title: 'Section $index',
                  message: 'Content',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Moderation claim card shows pending count and handles tap', (
    tester,
  ) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClaimRequestsModerationCard(
            countStream: Stream.value(1),
            onTap: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Claim requests'), findsOneWidget);
    expect(find.text('1 pending'), findsOneWidget);

    await tester.tap(find.text('Claim requests'));
    expect(opened, isTrue);
  });

  testWidgets('Moderation claim card has a neutral empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClaimRequestsModerationCard(
            countStream: Stream.value(0),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No pending claims'), findsOneWidget);
  });

  testWidgets(
    'Claim review list shows claim details and refreshes after action',
    (tester) async {
      final controller = StreamController<List<ClaimReviewItem>>();
      var approved = false;
      var rejected = false;
      const claim = ClaimReviewItem(
        id: 'claim-1',
        listingId: 'business-1',
        listingType: 'business',
        listingTitle: 'Tedsbakeryvan',
        claimantName: 'Mollie Rhodes',
        relationship: 'owner',
        email: 'mollie@example.com',
        phone: '07983509467',
        createdAt: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClaimReviewList(
              claimsStream: controller.stream,
              onOpen: (_) {},
              onApprove: (_) {
                approved = true;
                controller.add(const []);
              },
              onReject: (_) {
                rejected = true;
                controller.add(const []);
              },
            ),
          ),
        ),
      );

      controller.add(const [claim]);
      await tester.pump();

      expect(find.text('Tedsbakeryvan'), findsOneWidget);
      expect(find.text('BUSINESS'), findsOneWidget);
      expect(find.text('Claimant: Mollie Rhodes'), findsOneWidget);
      expect(find.text('Role: owner'), findsOneWidget);
      expect(find.text('Email: mollie@example.com'), findsOneWidget);
      expect(find.text('Phone: 07983509467'), findsOneWidget);
      expect(find.text('View listing'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pump();

      expect(approved, isTrue);
      expect(rejected, isFalse);
      expect(find.text('No pending claims'), findsOneWidget);

      await controller.close();
    },
  );

  test('Moderation screen separates Populate Area, claims and reports', () {
    final source = File(
      'lib/screens/admin_reports_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'Add and manage unclaimed businesses, organisations and events.',
      ),
    );
    expect(source, isNot(contains('then review ownership claims')));
    expect(source, contains('ClaimRequestsModerationCard'));
    expect(source, contains('ClaimReviewScreen'));
    expect(source, contains('_EmptyReports'));
  });

  test(
    'Populate Area no longer embeds claim review or area metrics dashboard',
    () {
      final source = File(
        'lib/screens/moderator_populate_area_screen.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('class _DashboardSummary')));
      expect(source, isNot(contains('Area population')));
      expect(source, isNot(contains('Businesses total')));
      expect(source, isNot(contains('Pending claims')));
      expect(source, isNot(contains('class _ClaimsSection')));
      expect(source, isNot(contains('Claim requests could not be loaded.')));
    },
  );

  test('Populate Area keeps listing creation, sharing and filters', () {
    final source = File(
      'lib/screens/moderator_populate_area_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Add listing'));
    expect(source, contains('Business'));
    expect(source, contains('Organisation'));
    expect(source, contains('Standalone Event'));
    expect(source, contains('Business added'));
    expect(source, contains('Share with business'));
    expect(source, contains('Existing listings'));
    expect(source, contains('Area filter'));
    expect(source, contains("ButtonSegment(value: 'all'"));
    expect(source, contains("ButtonSegment(value: 'unclaimed'"));
    expect(source, contains("ButtonSegment(value: 'claimed'"));
    expect(source, contains('No listings found in this area.'));
  });
}

class _MemoryHomeCategoryPreferences implements HomeCategoryPreferences {
  HomeDiscoveryCategory? selected;

  @override
  Future<HomeDiscoveryCategory?> load() async => selected;

  @override
  Future<void> save(HomeDiscoveryCategory category) async {
    selected = category;
  }
}

class _FakeAddressSearchService extends AddressSearchService {
  @override
  Future<List<AddressResult>> search(String query) async {
    if (query.length < 3) return [];
    return [
      AddressResult(
        description: 'Community Hall, High Street',
        placeId: 'place-1',
      ),
    ];
  }

  @override
  Future<Map<String, double>?> getCoordinates(String placeId) async {
    return {'lat': 52.1, 'lng': -1.9};
  }
}
