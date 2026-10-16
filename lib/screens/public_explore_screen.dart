import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/public_explore_preview.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class PublicExploreScreen extends StatefulWidget {
  const PublicExploreScreen({super.key, this.initialArea = ''});

  final String initialArea;

  static Widget? fromUri({required Uri uri}) {
    final route = PublicExploreRoute.fromUri(uri);
    if (route == null) return null;
    return PublicExploreScreen(initialArea: route.area);
  }

  @override
  State<PublicExploreScreen> createState() => _PublicExploreScreenState();
}

class _PublicExploreScreenState extends State<PublicExploreScreen> {
  static const _areas = ['Burntwood', 'Lichfield', 'Tamworth', 'Shrewsbury'];
  static const _filters = ['All', 'Services', 'Activities', 'Community Help'];

  late String _area = widget.initialArea;
  String _filter = 'All';
  late Future<List<PublicExplorePreview>> _previewsFuture = _loadPreviews();

  Future<List<PublicExplorePreview>> _loadPreviews() async {
    final result = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('getPublicExplorePreviews').call({'area': _area});
    final rawItems = result.data is Map
        ? (result.data as Map)['items']
        : result.data;
    final items = rawItems is List ? rawItems : const [];

    return items
        .whereType<Map>()
        .map(
          (item) =>
              PublicExplorePreview.fromData(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.publicUri != null)
        .toList(growable: false);
  }

  void _setArea(String area) {
    if (_area == area) return;
    setState(() {
      _area = area;
      _previewsFuture = _loadPreviews();
    });
  }

  List<PublicExplorePreview> _applyFilter(List<PublicExplorePreview> items) {
    if (_filter == 'All') return items;
    return items
        .where((item) {
          switch (_filter) {
            case 'Services':
              return item.type == 'business' ||
                  item.type == 'service' ||
                  item.type == 'availability';
            case 'Activities':
              return item.type == 'activity' || item.type == 'opportunity';
            case 'Community Help':
              return item.type == 'communityHelp';
          }
          return true;
        })
        .toList(growable: false);
  }

  void _openSignIn() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _openCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 840;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<List<PublicExplorePreview>>(
          future: _previewsFuture,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <PublicExplorePreview>[];
            final visibleItems = _applyFilter(items);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isWide ? 40 : 22,
                          isWide ? 28 : 18,
                          isWide ? 40 : 22,
                          12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ExploreHeader(onSignIn: _openSignIn),
                            SizedBox(height: isWide ? 40 : 28),
                            _ExploreHero(
                              isWide: isWide,
                              onCreateAccount: _openCreateAccount,
                              onSignIn: _openSignIn,
                            ),
                            const SizedBox(height: 24),
                            _AreaChips(
                              areas: _areas,
                              selectedArea: _area,
                              onSelected: _setArea,
                            ),
                            const SizedBox(height: 14),
                            _FilterChips(
                              filters: _filters,
                              selectedFilter: _filter,
                              onSelected: (filter) =>
                                  setState(() => _filter = filter),
                            ),
                            if (snapshot.connectionState !=
                                ConnectionState.done) ...[
                              const SizedBox(height: 44),
                              const Center(child: CircularProgressIndicator()),
                            ] else if (snapshot.hasError) ...[
                              const SizedBox(height: 24),
                              _EmptyState(
                                icon: Icons.wifi_off_rounded,
                                title: 'Explore is having a moment',
                                subtitle:
                                    'Please try again shortly. The LocalLink app is still available for signed-in members.',
                                onSignIn: _openSignIn,
                              ),
                            ] else if (visibleItems.isEmpty) ...[
                              const SizedBox(height: 24),
                              _EmptyState(
                                icon: Icons.travel_explore_rounded,
                                title: _area.isEmpty
                                    ? 'No public previews yet'
                                    : 'Nothing public for $_area yet',
                                subtitle:
                                    'Create an account to post, enquire, message and see the full local experience.',
                                onSignIn: _openSignIn,
                              ),
                            ] else ...[
                              const SizedBox(height: 24),
                              _PreviewGrid(
                                items: visibleItems,
                                isWide: isWide,
                                onSignIn: _openSignIn,
                              ),
                            ],
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => launchUrl(Uri(path: '/'), webOnlyWindowName: '_self'),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              SizedBox(
                height: 36,
                child: Image.asset('assets/images/locallink_logo.png'),
              ),
            ],
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onSignIn,
          style: TextButton.styleFrom(foregroundColor: AppColors.charcoal),
          child: const Text(
            'Sign in',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _ExploreHero extends StatelessWidget {
  const _ExploreHero({
    required this.isWide,
    required this.onCreateAccount,
    required this.onSignIn,
  });

  final bool isWide;
  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'See what is happening nearby',
          style: TextStyle(
            color: AppColors.charcoal,
            fontSize: 38,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Browse a limited public preview of local services, activities and Community Help posts. Sign in to message, book, follow or post.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: onCreateAccount,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.buttonPrimary,
                foregroundColor: AppColors.buttonText,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              child: const Text('Create account'),
            ),
            OutlinedButton(
              onPressed: onSignIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.charcoal,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    );

    const pills = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _CapabilityPill(
          label: 'Message local providers',
          color: AppColors.serviceGreen,
        ),
        _CapabilityPill(
          label: 'Join activities',
          color: AppColors.activityBlue,
        ),
        _CapabilityPill(
          label: 'Follow missing alerts',
          color: AppColors.primary,
        ),
        _CapabilityPill(
          label: 'Keep private details protected',
          color: AppColors.success,
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isWide ? 34 : 24),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: copy),
                  const SizedBox(width: 34),
                  Expanded(flex: 4, child: pills),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 24), pills],
              ),
      ),
    );
  }
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _AreaChips extends StatelessWidget {
  const _AreaChips({
    required this.areas,
    required this.selectedArea,
    required this.onSelected,
  });

  final List<String> areas;
  final String selectedArea;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ChoiceChipButton(
          label: 'Nearby examples',
          selected: selectedArea.isEmpty,
          onTap: () => onSelected(''),
        ),
        for (final area in areas)
          _ChoiceChipButton(
            label: area,
            selected: selectedArea.toLowerCase() == area.toLowerCase(),
            onTap: () => onSelected(area),
          ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filters,
    required this.selectedFilter,
    required this.onSelected,
  });

  final List<String> filters;
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final filter in filters)
          _ChoiceChipButton(
            label: filter,
            selected: selectedFilter == filter,
            onTap: () => onSelected(filter),
          ),
      ],
    );
  }
}

class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: .12) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: .45)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewGrid extends StatelessWidget {
  const _PreviewGrid({
    required this.items,
    required this.isWide,
    required this.onSignIn,
  });

  final List<PublicExplorePreview> items;
  final bool isWide;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 3 : 1,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: isWide ? .86 : 1.14,
      ),
      itemBuilder: (context, index) =>
          _PublicPreviewCard(item: items[index], onSignIn: onSignIn),
    );
  }
}

class _PublicPreviewCard extends StatelessWidget {
  const _PublicPreviewCard({required this.item, required this.onSignIn});

  final PublicExplorePreview item;
  final VoidCallback onSignIn;

  Color get _accent {
    switch (item.type) {
      case 'business':
      case 'service':
      case 'availability':
        return AppColors.serviceGreen;
      case 'activity':
      case 'opportunity':
        return AppColors.activityBlue;
      case 'communityHelp':
        return AppColors.primary;
    }
    return AppColors.primary;
  }

  IconData get _icon {
    switch (item.type) {
      case 'business':
      case 'service':
      case 'availability':
        return Icons.handshake_outlined;
      case 'activity':
      case 'opportunity':
        return Icons.event_available_outlined;
      case 'communityHelp':
        return Icons.volunteer_activism_outlined;
    }
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 142,
              width: double.infinity,
              child: item.hasImage
                  ? Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _ImageFallback(color: _accent, icon: _icon),
                    )
                  : _ImageFallback(color: _accent, icon: _icon),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (item.location.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              item.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => launchUrl(
                            item.publicUri!,
                            webOnlyWindowName: '_self',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.charcoal,
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: const Text('Preview'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: onSignIn,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.buttonPrimary,
                              foregroundColor: AppColors.buttonText,
                            ),
                            child: const Text('Sign in'),
                          ),
                        ),
                      ],
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

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: .1),
      child: Center(child: Icon(icon, color: color, size: 42)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSignIn,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 38),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
          ],
        ),
      ),
    );
  }
}
