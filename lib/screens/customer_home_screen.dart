import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

import '../models/ask_locallink.dart';
import '../screens/business_post_availability_gate_screen.dart';
import '../screens/business_onboarding_screen.dart';
import '../screens/business_detail_screen.dart';
import '../screens/create_choice_screen.dart';
import '../screens/create_opportunity_screen.dart';
import '../screens/customer_service_request_screen.dart';
import '../screens/availability_detail_screen.dart';
import '../screens/opportunity_detail_screen.dart';
import '../screens/opportunity_map_screen.dart';
import '../screens/organisation_detail_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../services/analytics_service.dart';
import '../services/ask_locallink_service.dart';
import '../services/auth_required_action.dart';
import '../services/business_access_service.dart';
import '../services/home_business_discovery_policy.dart';
import '../services/home_category_preferences.dart';
import '../services/home_feed_rules.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_surface_card.dart';
import '../widgets/opportunity_feed.dart';
import '../widgets/welcome_header.dart';

typedef AskLocalLinkSearch =
    Future<AskLocalLinkResponse> Function(
      String query, {
      AskLocalLinkQueryContext context,
    });
typedef AskLocalLinkContextResolver =
    Future<AskLocalLinkQueryContext> Function(String query);
typedef AskLocalLinkResultOpener =
    Future<void> Function(BuildContext context, AskLocalLinkResult result);

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    this.rootRequests,
    this.showLiveDiscovery = true,
    this.showBusinessAvailabilityAction = true,
    this.header,
    this.askSearch,
    this.askResultOpener,
    this.exploreNearbyOpener,
    this.homeCategoryPreferences,
  });

  final ValueListenable<int>? rootRequests;

  @visibleForTesting
  final bool showLiveDiscovery;

  @visibleForTesting
  final bool showBusinessAvailabilityAction;

  @visibleForTesting
  final Widget? header;

  @visibleForTesting
  final AskLocalLinkSearch? askSearch;

  @visibleForTesting
  final AskLocalLinkResultOpener? askResultOpener;

  @visibleForTesting
  final VoidCallback? exploreNearbyOpener;

  @visibleForTesting
  final HomeCategoryPreferences? homeCategoryPreferences;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _homeContentKey = GlobalKey();
  VoidCallback? _rootRequestListener;
  String? _browsingLocality;

  @override
  void initState() {
    super.initState();
    _bindRootRequests();
  }

  @override
  void didUpdateWidget(CustomerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootRequests != widget.rootRequests) {
      _unbindRootRequests(oldWidget.rootRequests);
      _bindRootRequests();
    }
  }

  @override
  void dispose() {
    _unbindRootRequests(widget.rootRequests);
    _scrollController.dispose();
    super.dispose();
  }

  void _bindRootRequests() {
    final requests = widget.rootRequests;
    if (requests == null) return;

    _rootRequestListener = () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    };
    requests.addListener(_rootRequestListener!);
  }

  void _unbindRootRequests(ValueListenable<int>? requests) {
    final listener = _rootRequestListener;
    if (requests == null || listener == null) return;

    requests.removeListener(listener);
    _rootRequestListener = null;
  }

  void _scrollToHomeContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _homeContentKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.04,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LocalLinkSpacing.lg,
                LocalLinkSpacing.md,
                LocalLinkSpacing.lg,
                LocalLinkSpacing.xl,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    widget.header ?? WelcomeHeader(locality: _browsingLocality),
                    const SizedBox(height: LocalLinkSpacing.sm),
                    AskLocalLinkPanel(
                      search:
                          widget.askSearch ??
                          (
                            query, {
                            context = const AskLocalLinkQueryContext(),
                          }) => AskLocalLinkService().search(
                            query: query,
                            context: context,
                          ),
                      resultOpener:
                          widget.askResultOpener ?? _openAskLocalLinkResult,
                      onBrowseManually: _scrollToHomeContent,
                      contextResolver: _resolveAskLocalLinkContext,
                    ),
                    const SizedBox(height: LocalLinkSpacing.sm),
                    _HomeContentSection(
                      key: _homeContentKey,
                      showLiveDiscovery: widget.showLiveDiscovery,
                      showBusinessAvailabilityAction:
                          widget.showBusinessAvailabilityAction,
                      preferences:
                          widget.homeCategoryPreferences ??
                          DeviceHomeCategoryPreferences(),
                      exploreNearbyOpener: widget.exploreNearbyOpener,
                      onLocalityChanged: (locality) {
                        if (_browsingLocality == locality || !mounted) return;
                        setState(() => _browsingLocality = locality);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openAskLocalLinkResult(
  BuildContext context,
  AskLocalLinkResult result,
) async {
  if (kDebugMode) {
    debugPrint(
      'AskLocalLink opener: '
      'type=${result.type}, '
      'id=${result.id}, '
      'parentId=${result.parentId}, '
      'route=${result.route}',
    );
  }

  switch (result.type) {
    case 'service':
      final businessId = result.parentId.trim();
      if (businessId.isEmpty) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDetailScreen(
            businessId: businessId,
            initialServiceId: result.id,
          ),
        ),
      );
      return;
    case 'business':
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDetailScreen(businessId: result.id),
        ),
      );
      return;
    case 'availability':
      await _openAvailabilityResult(context, result.id);
      return;
    case 'activity':
      await _openActivityResult(context, result.id);
      return;
    case 'organisation':
    case 'group':
      final organisationId = result.type == 'group'
          ? result.parentId.trim()
          : result.id.trim();
      if (organisationId.isEmpty) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OrganisationDetailScreen(organisationId: organisationId),
        ),
      );
      return;
    case 'communityHelp':
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostServiceRequestScreen(initialPostId: result.id),
        ),
      );
      return;
    case 'action':
      await _openAskLocalLinkAction(context, result);
      return;
  }
}

Future<void> _openAskLocalLinkAction(
  BuildContext context,
  AskLocalLinkResult result,
) async {
  Future<void> open(Widget screen) {
    return Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  final actionIntent = result.actionIntent;
  switch (actionIntent) {
    case 'report_missing_pet':
    case 'report_lost_item':
    case 'report_found_item':
    case 'give_away_item':
      await AuthRequiredAction.run(
        context,
        action: () async {
          await open(
            PostServiceRequestScreen(
              initialDraft: CommunityHelpInitialDraft(
                type: _metadataText(
                  result,
                  'communityHelpType',
                  fallback: 'lost_found',
                ),
                mode: _metadataText(result, 'mode', fallback: 'lost'),
                itemCategory: _metadataText(
                  result,
                  'itemCategory',
                  fallback: 'Other',
                ),
                petType: _metadataText(result, 'petType'),
              ),
            ),
          );
        },
      );
      return;
    case 'create_activity':
      await AuthRequiredAction.run(
        context,
        action: () async {
          await open(
            CreateOpportunityScreen(
              initialCategory: _metadataText(result, 'activityCategory'),
            ),
          );
        },
      );
      return;
    case 'list_business':
      await AuthRequiredAction.run(
        context,
        action: () async {
          await open(
            BusinessOnboardingScreen(
              initialCategory: _metadataText(result, 'businessCategory'),
            ),
          );
        },
      );
      return;
  }
}

String _metadataText(
  AskLocalLinkResult result,
  String key, {
  String fallback = '',
}) {
  final value = result.metadata[key]?.toString().trim() ?? '';
  return value.isEmpty ? fallback : value;
}

Future<AskLocalLinkQueryContext> _resolveAskLocalLinkContext(
  String query,
) async {
  final position = await LocationService().getCurrentLocation().timeout(
    const Duration(seconds: 2),
    onTimeout: () => null,
  );
  if (position == null) {
    return const AskLocalLinkQueryContext();
  }

  var locationText = '';
  try {
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    locationText = placemarks
        .expand(
          (place) => [
            place.locality,
            place.subLocality,
            place.subAdministrativeArea,
            place.administrativeArea,
          ],
        )
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  } catch (_) {
    locationText = '';
  }

  return AskLocalLinkQueryContext(
    locationText: locationText,
    latitude: position.latitude,
    longitude: position.longitude,
    radiusMiles: HomeBusinessDiscoveryPolicy.maximumRadiusMiles,
  );
}

Future<void> _openActivityResult(BuildContext context, String id) async {
  final doc = await FirebaseFirestore.instance
      .collection('opportunities')
      .doc(id)
      .get();
  final data = doc.data();
  if (!context.mounted || !doc.exists || data == null) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          OpportunityDetailScreen(opportunityId: id, opportunity: data),
    ),
  );
}

Future<void> _openAvailabilityResult(BuildContext context, String id) async {
  final doc = await FirebaseFirestore.instance
      .collection('availabilityPosts')
      .doc(id)
      .get();
  final data = doc.data();
  if (!context.mounted || !doc.exists || data == null) return;

  final businessId = data['businessId']?.toString().trim() ?? '';
  Map<String, dynamic> businessData = {};
  if (businessId.isNotEmpty) {
    final businessDoc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .get();
    businessData = businessDoc.data() ?? {};
  }
  if (!context.mounted) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AvailabilityDetailScreen(
        postId: id,
        availabilityData: data,
        businessData: businessData,
      ),
    ),
  );
}

class AskLocalLinkPanel extends StatefulWidget {
  const AskLocalLinkPanel({
    super.key,
    required this.search,
    required this.resultOpener,
    required this.onBrowseManually,
    this.contextResolver,
  });

  final AskLocalLinkSearch search;
  final AskLocalLinkResultOpener resultOpener;
  final VoidCallback onBrowseManually;
  final AskLocalLinkContextResolver? contextResolver;

  @override
  State<AskLocalLinkPanel> createState() => _AskLocalLinkPanelState();
}

class _AskLocalLinkPanelState extends State<AskLocalLinkPanel> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  AskLocalLinkResponse? _response;
  String? _error;
  String _lastQuery = '';
  bool _loading = false;
  int _submissionSequence = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value]) async {
    if (_loading) {
      _debugLog('ignored submit while request is already loading');
      return;
    }
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    final requestId = ++_submissionSequence;

    _debugLog(
      'submit[$requestId]: '
      'visibleText="${_controller.text}", '
      'submittedValue="${value ?? ''}", '
      'query="$query"',
    );

    setState(() {
      _loading = true;
      _error = null;
      _response = null;
      _lastQuery = query;
      _controller.text = query;
    });

    try {
      final context = await _resolveContext(query);
      _debugLog(
        'context[$requestId]: '
        'locationText="${context.locationText}", '
        'latitude=${context.latitude}, '
        'longitude=${context.longitude}, '
        'radiusMiles=${context.radiusMiles}',
      );
      final response = await widget.search(query, context: context);
      _debugLogResponse('response[$requestId]', response);
      await LocalLinkAnalytics.instance.askLocalLinkSearch(
        intentType: response.intent.intent,
        resultCount: response.results.length,
      );
      final actionResult = _firstActionResult(response.results);
      if (actionResult != null) {
        await LocalLinkAnalytics.instance.askLocalLinkActionSuggested(
          actionIntent: actionResult.actionIntent,
        );
      }
      if (!mounted) return;
      if (requestId != _submissionSequence) {
        _debugLog(
          'discarded response[$requestId] because a newer request exists',
        );
        return;
      }
      _debugLogResponse('setState[$requestId]', response);
      setState(() => _response = response);
    } catch (error) {
      if (!mounted) return;
      _debugLog(
        'error[$requestId]: Ask LocalLink request failed '
        '(${error.runtimeType})',
      );
      setState(() {
        _error = "Ask LocalLink isn't available right now.";
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<AskLocalLinkQueryContext> _resolveContext(String query) async {
    final resolver = widget.contextResolver;
    if (resolver == null) return const AskLocalLinkQueryContext();
    try {
      return await resolver(query);
    } catch (_) {
      _debugLog('context resolver failed; using empty context');
      return const AskLocalLinkQueryContext();
    }
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('AskLocalLinkPanel: $message');
  }

  void _debugLogResponse(String prefix, AskLocalLinkResponse response) {
    if (!kDebugMode) return;
    _debugLog(
      '$prefix: '
      'status=${response.status}, '
      'intent=${response.intent.intent}, '
      'category=${response.intent.category}, '
      'locationText=${response.intent.location?.text ?? ''}, '
      'latitude=${response.intent.location?.latitude}, '
      'longitude=${response.intent.location?.longitude}, '
      'radiusMiles=${response.intent.location?.radiusMiles}, '
      'resultCount=${response.results.length}',
    );
    for (var index = 0; index < response.results.length; index += 1) {
      final result = response.results[index];
      _debugLog(
        '$prefix result[$index]: '
        'type=${result.type}, '
        'id=${result.id}, '
        'route=${result.route}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalLinkSurfaceCard(
          key: const ValueKey('ask-locallink-entry-card'),
          elevated: true,
          color: AppColors.primaryDeep,
          padding: const EdgeInsets.all(LocalLinkSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AskHeader(),
              const SizedBox(height: LocalLinkSpacing.xs),
              Semantics(
                textField: true,
                label: 'Ask LocalLink search',
                child: TextField(
                  key: const ValueKey('ask-locallink-search-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !_loading,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  minLines: 1,
                  maxLines: 2,
                  style: LocalLinkTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'What do you need locally?',
                    hintMaxLines: 2,
                    hintStyle: LocalLinkTextStyles.secondary.copyWith(
                      color: AppColors.textLight,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textMuted,
                    ),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Search',
                            color: AppColors.primary,
                            icon: const Icon(Icons.arrow_forward_rounded),
                            onPressed: () => _submit(),
                          ),
                    filled: true,
                    fillColor: AppColors.elevatedSurface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: LocalLinkSpacing.md,
                      vertical: LocalLinkSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_loading) ...[
          const SizedBox(height: LocalLinkSpacing.md),
          const _AskStatusCard(
            icon: Icons.auto_awesome_rounded,
            title: 'Searching LocalLink...',
            message: 'Checking services, availability, activities and help.',
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: LocalLinkSpacing.md),
          _AskFailureCard(
            message: _error!,
            onRetry: _lastQuery.isEmpty ? null : () => _submit(_lastQuery),
            onBrowseManually: widget.onBrowseManually,
          ),
        ] else if (response != null) ...[
          const SizedBox(height: LocalLinkSpacing.md),
          _AskResultsView(
            query: _lastQuery,
            response: response,
            onOpenResult: (result, index) async {
              if (result.isAction) {
                await LocalLinkAnalytics.instance.askLocalLinkActionOpened(
                  actionIntent: result.actionIntent,
                );
              } else {
                await LocalLinkAnalytics.instance.askLocalLinkResultOpened(
                  resultType: result.type,
                  resultPosition: index + 1,
                  intentType: response.intent.intent,
                );
              }
              if (!context.mounted) return;
              await widget.resultOpener(context, result);
            },
            onBrowseManually: widget.onBrowseManually,
          ),
        ],
      ],
    );
  }
}

AskLocalLinkResult? _firstActionResult(List<AskLocalLinkResult> results) {
  for (final result in results) {
    if (result.isAction) return result;
  }
  return null;
}

class _AskHeader extends StatelessWidget {
  const _AskHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: LocalLinkSpacing.xs),
            Expanded(
              child: Text(
                'Ask LocalLink',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LocalLinkTextStyles.cardTitle.copyWith(
                  color: AppColors.inverseText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LocalLinkSpacing.xxs),
        Text(
          'What can we help you find locally?',
          style: LocalLinkTextStyles.secondary.copyWith(
            color: AppColors.inverseText.withValues(alpha: 0.94),
          ),
        ),
      ],
    );
  }
}

class _AskResultsView extends StatelessWidget {
  const _AskResultsView({
    required this.query,
    required this.response,
    required this.onOpenResult,
    required this.onBrowseManually,
  });

  final String query;
  final AskLocalLinkResponse response;
  final Future<void> Function(AskLocalLinkResult result, int index)
  onOpenResult;
  final VoidCallback onBrowseManually;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint(
        'AskLocalLinkResultsView: '
        'status=${response.status}, '
        'intent=${response.intent.intent}, '
        'resultCount=${response.results.length}, '
        'query="$query"',
      );
      for (var index = 0; index < response.results.length; index += 1) {
        final result = response.results[index];
        debugPrint(
          'AskLocalLinkResultsView result[$index]: '
          'type=${result.type}, '
          'id=${result.id}, '
          'route=${result.route}',
        );
      }
    }

    if (response.isUnknown) {
      return _UnknownIntentCard(onExampleSelected: onBrowseManually);
    }

    if (response.results.isEmpty) {
      return _NoResultsCard(
        intent: response.intent.intent,
        onBrowseManually: onBrowseManually,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _resultTitle(response.intent, query),
          style: LocalLinkTextStyles.cardTitle,
        ),
        const SizedBox(height: LocalLinkSpacing.sm),
        ...response.results.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
            child: _AskResultCard(
              result: entry.value,
              onTap: () {
                onOpenResult(entry.value, entry.key);
              },
            ),
          ),
        ),
      ],
    );
  }

  String _resultTitle(AskLocalLinkIntent intent, String query) {
    final text = query.trim();
    if (text.isNotEmpty) return text;
    return switch (intent.intent) {
      'find_availability' => 'Available locally',
      'find_service' => 'Local services',
      'find_activity' => 'Local activities',
      'find_organisation' => 'Local organisations',
      'find_community_help' => 'Community Help',
      _ => 'LocalLink results',
    };
  }
}

class _AskResultCard extends StatelessWidget {
  const _AskResultCard({required this.result, required this.onTap});

  final AskLocalLinkResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (result.isAction) {
      return _AskActionResultCard(result: result, onTap: onTap);
    }

    final accent = _accentForType(result.type);
    final isChallenge = _isCommunityChallenge(result);
    final challengeCloseLabel = _challengeCloseLabel(context, result);
    final prize = _metadataText(result, 'prizeDescription');
    return LocalLinkSurfaceCard(
      onTap: onTap,
      elevated: false,
      radius: LocalLinkRadius.md,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeActionIcon(icon: _iconForType(result.type), color: accent),
          const SizedBox(width: LocalLinkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_availabilityLabel(context, result).isNotEmpty) ...[
                  _AvailabilityPill(label: _availabilityLabel(context, result)),
                  const SizedBox(height: LocalLinkSpacing.xs),
                ],
                Text(
                  result.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 15.5),
                ),
                if (result.subtitle.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    result.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.secondary,
                  ),
                ],
                if (isChallenge && challengeCloseLabel.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: LocalLinkSpacing.xxs),
                      Expanded(
                        child: Text(
                          challengeCloseLabel,
                          style: LocalLinkTextStyles.metadata.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (isChallenge && prize.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Row(
                    children: [
                      Icon(
                        Icons.card_giftcard_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: LocalLinkSpacing.xxs),
                      Expanded(
                        child: Text(
                          prize,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LocalLinkTextStyles.metadata,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _typeLabelForResult(result),
                      style: LocalLinkTextStyles.metadata.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (result.distanceMiles != null)
                      Text(
                        '${result.distanceMiles} miles',
                        style: LocalLinkTextStyles.metadata,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }

  String _availabilityLabel(BuildContext context, AskLocalLinkResult result) {
    if (result.type != 'availability') return '';
    final raw = result.dateTime;
    if (raw == null || raw.isEmpty) return 'Available';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Available';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(date.year, date.month, date.day);
    final dayLabel = value == today
        ? 'today'
        : value == today.add(const Duration(days: 1))
        ? 'tomorrow'
        : '${date.day}/${date.month}';
    final time = TimeOfDay.fromDateTime(date).format(context);
    return 'Available $dayLabel · $time';
  }

  Color _accentForType(String type) {
    return switch (type) {
      'availability' || 'service' || 'business' => AppColors.serviceGreen,
      'activity' || 'organisation' || 'group' => AppColors.activityBlue,
      'communityHelp' || 'action' => AppColors.primary,
      _ => AppColors.primary,
    };
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'availability' => Icons.event_available_rounded,
      'service' || 'business' => Icons.design_services_outlined,
      'activity' => Icons.groups_2_outlined,
      'organisation' || 'group' => Icons.account_tree_outlined,
      'communityHelp' => Icons.volunteer_activism_outlined,
      'action' => Icons.arrow_circle_right_outlined,
      _ => Icons.search_rounded,
    };
  }

  bool _isCommunityChallenge(AskLocalLinkResult result) {
    return result.type == 'activity' &&
        _metadataText(result, 'activityKind') == 'community_challenge';
  }

  String _challengeCloseLabel(BuildContext context, AskLocalLinkResult result) {
    final raw = _metadataText(result, 'challengeClosesAt');
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    final dateLabel = MaterialLocalizations.of(context).formatShortDate(date);
    final isOpen = result.metadata['isOpenForEntry'] != false;
    return isOpen ? 'Entries close $dateLabel' : 'Closed $dateLabel';
  }

  String _typeLabelForResult(AskLocalLinkResult result) {
    if (_isCommunityChallenge(result)) return 'Community Challenge';
    return _typeLabel(result.type);
  }

  String _typeLabel(String type) {
    return switch (type) {
      'availability' => 'Availability',
      'service' => 'Service',
      'business' => 'Business',
      'activity' => 'Activity',
      'organisation' => 'Organisation',
      'group' => 'Group',
      'communityHelp' => 'Community Help',
      'action' => 'Action',
      _ => 'Result',
    };
  }
}

class _AskActionResultCard extends StatelessWidget {
  const _AskActionResultCard({required this.result, required this.onTap});

  final AskLocalLinkResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: onTap,
      elevated: false,
      radius: LocalLinkRadius.md,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeActionIcon(
                icon: _iconForAction(result.actionIntent),
                color: AppColors.primary,
              ),
              const SizedBox(width: LocalLinkSpacing.md),
              Expanded(
                child: Text(
                  result.title,
                  style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 16.5),
                ),
              ),
            ],
          ),
          if (result.subtitle.isNotEmpty) ...[
            const SizedBox(height: LocalLinkSpacing.sm),
            Text(
              result.subtitle,
              style: LocalLinkTextStyles.secondary.copyWith(height: 1.35),
            ),
          ],
          const SizedBox(height: LocalLinkSpacing.md),
          LocalLinkButton(
            key: ValueKey('ask-action-cta-${result.actionIntent}'),
            label: _ctaLabel(result),
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }

  IconData _iconForAction(String actionIntent) {
    return switch (actionIntent) {
      'report_missing_pet' => Icons.pets_outlined,
      'report_lost_item' => Icons.search_outlined,
      'report_found_item' => Icons.inventory_2_outlined,
      'give_away_item' => Icons.card_giftcard_outlined,
      'create_activity' => Icons.groups_2_outlined,
      'list_business' => Icons.storefront_outlined,
      _ => Icons.arrow_circle_right_outlined,
    };
  }

  String _ctaLabel(AskLocalLinkResult result) {
    return switch (result.actionIntent) {
      'report_missing_pet' => 'Start missing pet report',
      'report_lost_item' => 'Start lost item report',
      'report_found_item' => 'Start found item report',
      'give_away_item' => 'Start free item post',
      'create_activity' => 'Create activity',
      'list_business' => 'List my business',
      _ => result.title,
    };
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.wide = false,
    this.affordanceIcon = Icons.arrow_forward_rounded,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool wide;
  final IconData affordanceIcon;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return LocalLinkSurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        radius: LocalLinkRadius.sm,
        elevated: false,
        color: AppColors.elevatedSurface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeActionIcon(icon: icon, color: color),
              const SizedBox(height: LocalLinkSpacing.lg),
              _HomeActionText(title: title, subtitle: subtitle),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LocalLinkRadius.xs),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: LocalLinkSpacing.xxs,
            vertical: LocalLinkSpacing.xs,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: color.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
          ),
          child: Row(
            children: [
              _HomeActionIcon(icon: icon, color: color),
              const SizedBox(width: LocalLinkSpacing.sm),
              Expanded(
                child: _HomeActionText(title: title, subtitle: subtitle),
              ),
              const SizedBox(width: LocalLinkSpacing.sm),
              _HomeActionAffordance(icon: affordanceIcon, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActionAffordance extends StatelessWidget {
  const _HomeActionAffordance({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home-action-affordance'),
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: AppColors.inverseText, size: 20),
    );
  }
}

class _HomeActionIcon extends StatelessWidget {
  const _HomeActionIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LocalLinkRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _HomeActionText extends StatelessWidget {
  const _HomeActionText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 15.5),
        ),
        const SizedBox(height: LocalLinkSpacing.xxs),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LocalLinkTextStyles.metadata,
        ),
      ],
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.serviceGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
        border: Border.all(
          color: AppColors.serviceGreen.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LocalLinkSpacing.sm,
          vertical: 5,
        ),
        child: Text(
          label,
          style: LocalLinkTextStyles.metadata.copyWith(
            color: AppColors.serviceGreen,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AskStatusCard extends StatelessWidget {
  const _AskStatusCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      radius: LocalLinkRadius.md,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        children: [
          _HomeActionIcon(icon: icon, color: AppColors.primary),
          const SizedBox(width: LocalLinkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LocalLinkTextStyles.cardTitle),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(message, style: LocalLinkTextStyles.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AskFailureCard extends StatelessWidget {
  const _AskFailureCard({
    required this.message,
    required this.onRetry,
    required this.onBrowseManually,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onBrowseManually;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      radius: LocalLinkRadius.md,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: LocalLinkTextStyles.cardTitle),
          const SizedBox(height: LocalLinkSpacing.sm),
          Row(
            children: [
              Expanded(
                child: LocalLinkButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                  expand: true,
                ),
              ),
              const SizedBox(width: LocalLinkSpacing.sm),
              Expanded(
                child: LocalLinkButton(
                  label: 'Browse manually',
                  icon: Icons.tune_rounded,
                  variant: LocalLinkButtonVariant.secondary,
                  onPressed: onBrowseManually,
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnknownIntentCard extends StatelessWidget {
  const _UnknownIntentCard({required this.onExampleSelected});

  final VoidCallback onExampleSelected;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      radius: LocalLinkRadius.md,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "I'm not sure what you're looking for yet.",
            style: LocalLinkTextStyles.cardTitle,
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(
            'Try describing the local thing you need in a few words.',
            style: LocalLinkTextStyles.secondary,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkButton(
            label: 'Browse manually',
            icon: Icons.tune_rounded,
            variant: LocalLinkButtonVariant.secondary,
            onPressed: onExampleSelected,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _NoResultsCard extends StatelessWidget {
  const _NoResultsCard({required this.intent, required this.onBrowseManually});

  final String intent;
  final VoidCallback onBrowseManually;

  @override
  Widget build(BuildContext context) {
    final copy = switch (intent) {
      'find_availability' => (
        'No matching availability found right now.',
        'Create a service request',
      ),
      'find_service' => (
        'No matching services found right now.',
        'Browse services',
      ),
      'find_activity' => ('No matching activities found.', 'Browse activities'),
      'find_organisation' => (
        'No matching organisations found.',
        'Browse organisations',
      ),
      'find_community_help' => (
        'No matching Community Help posts found.',
        'View Community Help',
      ),
      _ => ('No matching LocalLink results found.', 'Browse manually'),
    };

    return LocalLinkSurfaceCard(
      elevated: false,
      radius: LocalLinkRadius.md,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(copy.$1, style: LocalLinkTextStyles.cardTitle),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(
            'Manual discovery is still available.',
            style: LocalLinkTextStyles.secondary,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkButton(
            label: copy.$2,
            icon: Icons.tune_rounded,
            variant: LocalLinkButtonVariant.secondary,
            onPressed: onBrowseManually,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _HomeContentSection extends StatefulWidget {
  const _HomeContentSection({
    super.key,
    required this.showLiveDiscovery,
    required this.showBusinessAvailabilityAction,
    required this.preferences,
    required this.onLocalityChanged,
    this.exploreNearbyOpener,
  });

  final bool showLiveDiscovery;
  final bool showBusinessAvailabilityAction;
  final HomeCategoryPreferences preferences;
  final ValueChanged<String?> onLocalityChanged;
  final VoidCallback? exploreNearbyOpener;

  @override
  State<_HomeContentSection> createState() => _HomeContentSectionState();
}

class _HomeContentSectionState extends State<_HomeContentSection> {
  HomeDiscoveryCategory _selectedCategory = HomeDiscoveryCategory.nearby;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCategory());
  }

  Future<void> _restoreCategory() async {
    final restored = await widget.preferences.load();
    if (!mounted || restored == null || restored == _selectedCategory) return;
    setState(() => _selectedCategory = restored);
  }

  void _selectCategory(HomeDiscoveryCategory category) {
    if (category == _selectedCategory) return;
    setState(() => _selectedCategory = category);
    unawaited(widget.preferences.save(category));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OpportunityFeed(
          initialCategory: _selectedCategory,
          onCategorySelected: _selectCategory,
          onLocalityChanged: widget.onLocalityChanged,
          showContent: widget.showLiveDiscovery,
          contextualActionsBuilder: (context, category) =>
              _HomeContextualAction(
                category: category,
                showBusinessAvailabilityAction:
                    widget.showBusinessAvailabilityAction,
                exploreNearbyOpener: widget.exploreNearbyOpener,
              ),
        ),
      ],
    );
  }
}

class _HomeContextualAction extends StatelessWidget {
  const _HomeContextualAction({
    required this.category,
    required this.showBusinessAvailabilityAction,
    this.exploreNearbyOpener,
  });

  final HomeDiscoveryCategory category;
  final bool showBusinessAvailabilityAction;
  final VoidCallback? exploreNearbyOpener;

  @override
  Widget build(BuildContext context) {
    return switch (category) {
      HomeDiscoveryCategory.nearby => _ExploreNearbyAction(
        onTap: exploreNearbyOpener,
      ),
      HomeDiscoveryCategory.services => _HomeActionCard(
        key: const ValueKey('home-contextual-action-services'),
        icon: Icons.design_services_outlined,
        title: 'Post what you need',
        subtitle: 'Tell local providers what you’re looking for',
        color: AppColors.serviceGreen,
        wide: true,
        affordanceIcon: Icons.add_rounded,
        onTap: () =>
            _openProtected(context, const CustomerServiceRequestScreen()),
      ),
      HomeDiscoveryCategory.activities => _HomeActionCard(
        key: const ValueKey('home-contextual-action-activities'),
        icon: Icons.groups_2_outlined,
        title: 'Add an activity or event',
        subtitle: 'Share something happening locally',
        color: AppColors.activityBlue,
        wide: true,
        affordanceIcon: Icons.add_rounded,
        onTap: () => _openProtected(context, const CreateChoiceScreen()),
      ),
      HomeDiscoveryCategory.communityHelp => _HomeActionCard(
        key: const ValueKey('home-contextual-action-communityHelp'),
        icon: Icons.volunteer_activism_outlined,
        title: 'Report something',
        subtitle: 'Lost pet, found item or local help',
        color: AppColors.communityTeal,
        wide: true,
        affordanceIcon: Icons.add_rounded,
        onTap: () => _openProtected(context, const PostServiceRequestScreen()),
      ),
      HomeDiscoveryCategory.businesses =>
        showBusinessAvailabilityAction
            ? FutureBuilder(
                future: BusinessAccessService.loadLinkedBusiness(),
                builder: (context, snapshot) => _HomeActionCard(
                  key: const ValueKey('home-contextual-action-businesses'),
                  icon: Icons.trending_up_rounded,
                  title: snapshot.data == null || !snapshot.data!.exists
                      ? 'Add or manage your business'
                      : 'Manage your business',
                  subtitle: snapshot.data == null || !snapshot.data!.exists
                      ? 'Promote your services locally'
                      : 'Share your availability',
                  color: AppColors.serviceGreen,
                  wide: true,
                  onTap: () =>
                      _openBusinessGrowthAction(context, snapshot.data),
                ),
              )
            : const SizedBox.shrink(),
      HomeDiscoveryCategory.organisations => _HomeActionCard(
        key: const ValueKey('home-contextual-action-organisations'),
        icon: Icons.hub_outlined,
        title: 'Add a group or organisation',
        subtitle: 'Help people discover your community',
        color: AppColors.activityBlue,
        wide: true,
        affordanceIcon: Icons.add_rounded,
        onTap: () => _openProtected(context, const CreateChoiceScreen()),
      ),
    };
  }

  void _openProtected(BuildContext context, Widget target) {
    AuthRequiredAction.run(
      context,
      action: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => target),
        );
      },
    );
  }

  Future<void> _openBusinessGrowthAction(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>>? business,
  ) async {
    final target = business != null && business.exists
        ? const BusinessPostAvailabilityGateScreen()
        : const BusinessOnboardingScreen();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _openProtected(context, target);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => target));
  }
}

class _ExploreNearbyAction extends StatelessWidget {
  const _ExploreNearbyAction({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeActionCard(
      key: const ValueKey('explore-nearby-action'),
      icon: Icons.map_outlined,
      title: "Explore what's nearby",
      subtitle:
          'See activities, groups, services and community help around you',
      color: AppColors.primary,
      wide: true,
      onTap:
          onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OpportunityMapScreen()),
            );
          },
    );
  }
}
