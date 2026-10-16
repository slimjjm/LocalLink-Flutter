import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/customer_home_screen.dart';
import 'package:locallink_flutter/services/home_category_preferences.dart';
import 'package:locallink_flutter/services/home_feed_rules.dart';
import 'package:locallink_flutter/theme/app_colors.dart';
import 'package:locallink_flutter/theme/local_link_theme.dart';
import 'package:locallink_flutter/widgets/local_link_chip.dart';
import 'package:locallink_flutter/widgets/local_link_surface_card.dart';
import 'package:locallink_flutter/widgets/opportunity_feed.dart';
import 'package:locallink_flutter/widgets/welcome_header.dart';

void main() {
  testWidgets('Home defaults to Nearby and saves a new category', (
    tester,
  ) async {
    final preferences = _MemoryHomeCategoryPreferences();

    await tester.pumpWidget(_home(preferences: preferences));
    await tester.pumpAndSettle();

    expect(_selectedChip(tester, 'Nearby').selected, isTrue);
    expect(_selectedChip(tester, 'Nearby').accentColor, AppColors.primary);
    expect(find.text("Explore what's nearby"), findsOneWidget);
    final liveStatus = find.byKey(const ValueKey('home-live-now-status'));
    expect(liveStatus, findsOneWidget);
    expect(
      find.descendant(of: liveStatus, matching: find.byType(LocalLinkChip)),
      findsNothing,
    );

    final nearbyAffordance = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('explore-nearby-action')),
        matching: find.byKey(const ValueKey('home-action-affordance')),
      ),
    );
    expect(
      (nearbyAffordance.decoration! as BoxDecoration).color,
      AppColors.primary,
    );

    await tester.tap(find.text('Community Help'));
    await tester.pumpAndSettle();

    expect(preferences.selected, HomeDiscoveryCategory.communityHelp);
    expect(_selectedChip(tester, 'Community Help').selected, isTrue);
    expect(find.text('Report something'), findsOneWidget);
    expect(find.text("Explore what's nearby"), findsNothing);
  });

  testWidgets('Ask LocalLink copy and input share one cohesive card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _home(preferences: _MemoryHomeCategoryPreferences()),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('ask-locallink-entry-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Ask LocalLink')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('What can we help you find locally?'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('ask-locallink-search-field')),
      ),
      findsOneWidget,
    );

    final askSurface = tester.widget<LocalLinkSurfaceCard>(card);
    expect(AppColors.primaryDeep, const Color(0xFFB8522F));
    expect(askSurface.color, AppColors.primaryDeep);
    expect(askSurface.elevated, isTrue);
    expect(
      _contrastRatio(AppColors.primaryDeep, AppColors.inverseText),
      greaterThanOrEqualTo(4.5),
    );
    final supportingTextColor = Color.alphaBlend(
      AppColors.inverseText.withValues(alpha: 0.94),
      AppColors.primaryDeep,
    );
    expect(
      _contrastRatio(AppColors.primaryDeep, supportingTextColor),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('greeting no longer uses the dark premium hero surface', () {
    final source = File('lib/widgets/welcome_header.dart').readAsStringSync();

    expect(source, isNot(contains('_PremiumHeaderSurface')));
    expect(source, isNot(contains('home-premium-header')));
  });

  testWidgets(
    'Explore header is concise and contextual actions stay distinct',
    (tester) async {
      await tester.pumpWidget(
        _home(
          preferences: _MemoryHomeCategoryPreferences(),
          showBusinessAction: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose what you want to see nearby.'), findsNothing);
      expect(
        find.byKey(const ValueKey('explore-nearby-action')),
        findsOneWidget,
      );

      for (final expectation in <(String, String, String, Color)>[
        (
          'Services',
          'Post what you need',
          'home-contextual-action-services',
          AppColors.serviceGreen,
        ),
        (
          'Activities',
          'Add an activity or event',
          'home-contextual-action-activities',
          AppColors.activityBlue,
        ),
        (
          'Community Help',
          'Report something',
          'home-contextual-action-communityHelp',
          AppColors.communityTeal,
        ),
        (
          'Businesses',
          'Add or manage your business',
          'home-contextual-action-businesses',
          AppColors.serviceGreen,
        ),
        (
          'Organisations',
          'Add a group or organisation',
          'home-contextual-action-organisations',
          AppColors.activityBlue,
        ),
      ]) {
        await tester.ensureVisible(find.text(expectation.$1));
        await tester.tap(find.text(expectation.$1));
        await tester.pumpAndSettle();

        final action = find.byKey(ValueKey(expectation.$3));
        expect(action, findsOneWidget);
        expect(
          find.descendant(of: action, matching: find.text(expectation.$2)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: action,
            matching: find.byType(LocalLinkSurfaceCard),
          ),
          findsNothing,
        );

        final selectedChip = _selectedChip(tester, expectation.$1);
        expect(selectedChip.selected, isTrue);
        expect(selectedChip.accentColor, expectation.$4);

        final category = HomeDiscoveryCategory.values.firstWhere(
          (value) => value.label == expectation.$1,
        );
        final indicator = find.byKey(
          ValueKey('home-category-indicator-${category.name}'),
        );
        expect(tester.getSize(indicator).width, 24);

        final affordance = tester.widget<Container>(
          find.descendant(
            of: action,
            matching: find.byKey(const ValueKey('home-action-affordance')),
          ),
        );
        final decoration = affordance.decoration! as BoxDecoration;
        expect(decoration.color, expectation.$4);
      }
    },
  );

  testWidgets('Home restores the last selected category', (tester) async {
    final preferences = _MemoryHomeCategoryPreferences(
      HomeDiscoveryCategory.activities,
    );

    await tester.pumpWidget(_home(preferences: preferences));
    await tester.pumpAndSettle();

    expect(_selectedChip(tester, 'Activities').selected, isTrue);
    expect(find.text('Add an activity or event'), findsOneWidget);
    expect(find.text('Share something happening locally'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected category automatically scrolls fully into view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = HomeDiscoveryCategory.nearby;
    late StateSetter updateSelection;

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateSelection = setState;
              return HomeDiscoveryCategoryTabs(
                selectedCategory: selected,
                onSelected: (category) {
                  setState(() => selected = category);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final organisations = find.byKey(
      const ValueKey('home-category-organisations'),
    );
    final organisationsLeftBeforeSwipe = tester.getRect(organisations).left;
    await tester.drag(
      find.byKey(const ValueKey('home-category-scroll')),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(organisations).left,
      lessThan(organisationsLeftBeforeSwipe),
    );
    updateSelection(() => selected = HomeDiscoveryCategory.organisations);
    await tester.pumpAndSettle();

    for (final category in HomeDiscoveryCategory.values) {
      updateSelection(() => selected = category);
      await tester.pumpAndSettle();

      final viewport = tester.getRect(
        find.byKey(const ValueKey('home-category-scroll')),
      );
      final selectedChip = tester.getRect(
        find.byKey(ValueKey('home-category-${category.name}')),
      );
      expect(selectedChip.left, greaterThanOrEqualTo(viewport.left));
      expect(selectedChip.right, lessThanOrEqualTo(viewport.right));
      expect(_selectedChip(tester, category.label).selected, isTrue);
    }
  });

  testWidgets('contextual action wraps without overflow on a narrow display', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _home(
        preferences: _MemoryHomeCategoryPreferences(
          HomeDiscoveryCategory.activities,
        ),
        textScaler: const TextScaler.linear(1.3),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add an activity or event'), findsOneWidget);
    expect(find.text('Share something happening locally'), findsOneWidget);
  });

  testWidgets('restoring a category starts a relaunched Home at the top', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = _MemoryHomeCategoryPreferences(
      HomeDiscoveryCategory.communityHelp,
    );

    await tester.pumpWidget(_home(preferences: preferences));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    final firstScroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(firstScroll.controller!.offset, greaterThan(0));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(_home(preferences: preferences));
    await tester.pumpAndSettle();

    final relaunchedScroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(relaunchedScroll.controller!.offset, 0);
    expect(_selectedChip(tester, 'Community Help').selected, isTrue);
  });

  test('location subtitle uses current locality or nearby fallback', () {
    expect(
      homeLocationSubtitle('Lichfield'),
      'Here’s what’s happening around Lichfield.',
    );
    expect(homeLocationSubtitle(null), 'Here’s what’s happening nearby.');
    expect(homeLocationSubtitle('  '), 'Here’s what’s happening nearby.');
  });

  test('Home categories apply distinct feed lenses', () {
    expect(
      HomeFeedRules.categoryAllowsType(
        HomeDiscoveryCategory.nearby,
        HomeFeedContentType.communityHelp,
      ),
      isTrue,
    );
    expect(
      HomeFeedRules.categoryAllowsType(
        HomeDiscoveryCategory.services,
        HomeFeedContentType.serviceRequest,
      ),
      isTrue,
    );
    expect(
      HomeFeedRules.categoryAllowsType(
        HomeDiscoveryCategory.services,
        HomeFeedContentType.activity,
      ),
      isFalse,
    );
    expect(
      HomeFeedRules.categoryAllowsType(
        HomeDiscoveryCategory.communityHelp,
        HomeFeedContentType.communityHelp,
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
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _home({
  required HomeCategoryPreferences preferences,
  bool showBusinessAction = false,
  TextScaler? textScaler,
}) {
  return MaterialApp(
    theme: LocalLinkTheme.light,
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: CustomerHomeScreen(
      showLiveDiscovery: false,
      showBusinessAvailabilityAction: showBusinessAction,
      header: const Text('Header'),
      homeCategoryPreferences: preferences,
    ),
  );
}

LocalLinkChip _selectedChip(WidgetTester tester, String label) {
  return tester.widget<LocalLinkChip>(
    find.widgetWithText(LocalLinkChip, label),
  );
}

class _MemoryHomeCategoryPreferences implements HomeCategoryPreferences {
  _MemoryHomeCategoryPreferences([this.selected]);

  HomeDiscoveryCategory? selected;

  @override
  Future<HomeDiscoveryCategory?> load() async => selected;

  @override
  Future<void> save(HomeDiscoveryCategory category) async {
    selected = category;
  }
}
