import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PublicLandingScaffold();
  }
}

class PublicCategoryLandingScreen extends StatelessWidget {
  const PublicCategoryLandingScreen({super.key, required this.category});

  final PublicLandingCategory category;

  static Widget? fromUri({required Uri uri}) {
    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length != 1) return null;

    final category = PublicLandingCategory.fromPath(segments.first);
    if (category == null) return null;
    return PublicCategoryLandingScreen(category: category);
  }

  @override
  Widget build(BuildContext context) {
    return _PublicLandingScaffold(initialCategory: category);
  }
}

class _PublicLandingScaffold extends StatelessWidget {
  const _PublicLandingScaffold({this.initialCategory});

  final PublicLandingCategory? initialCategory;

  void _openSignIn(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _openCreateAccount(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  void _openExplore() {
    launchUrl(Uri(path: '/explore'), webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 860;
    final selectedCategory = initialCategory;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 40 : 22,
                  vertical: isWide ? 28 : 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PublicHeader(
                      isWide: isWide,
                      onSignIn: () => _openSignIn(context),
                    ),
                    SizedBox(height: isWide ? 56 : 32),
                    _HeroSection(
                      isWide: isWide,
                      onCreateAccount: () => _openCreateAccount(context),
                      onSignIn: () => _openSignIn(context),
                      onExplore: _openExplore,
                    ),
                    SizedBox(height: isWide ? 54 : 34),
                    _PrimaryActionsGrid(isWide: isWide),
                    if (selectedCategory != null) ...[
                      SizedBox(height: isWide ? 40 : 28),
                      _CategorySection(category: selectedCategory),
                    ],
                    SizedBox(height: isWide ? 50 : 34),
                    _DiscoverySection(isWide: isWide),
                    SizedBox(height: isWide ? 44 : 30),
                    _CommunityHelpSection(isWide: isWide),
                    SizedBox(height: isWide ? 44 : 30),
                    _BusinessSection(isWide: isWide),
                    SizedBox(height: isWide ? 46 : 30),
                    _AppSection(onSignIn: () => _openSignIn(context)),
                    const SizedBox(height: 30),
                    const _PublicFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicHeader extends StatelessWidget {
  const _PublicHeader({required this.isWide, required this.onSignIn});

  final bool isWide;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          height: isWide ? 42 : 34,
          child: Image.asset('assets/images/locallink_logo.png'),
        ),
        const Spacer(),
        if (isWide) ...[
          const _HeaderLink(label: 'Explore', path: '/explore'),
          const _HeaderLink(label: 'Community Help', path: '/community-help'),
          const _HeaderLink(label: 'For businesses', path: '/businesses'),
          const SizedBox(width: 10),
        ],
        TextButton(
          onPressed: onSignIn,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.charcoal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text(
            'Sign in',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _HeaderLink extends StatelessWidget {
  const _HeaderLink({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => launchUrl(Uri(path: path), webOnlyWindowName: '_self'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.isWide,
    required this.onCreateAccount,
    required this.onSignIn,
    required this.onExplore,
  });

  final bool isWide;
  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: isWide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'Explore your community',
          textAlign: isWide ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: AppColors.charcoal,
            fontSize: isWide ? 64 : 40,
            fontWeight: FontWeight.w900,
            height: 1.02,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Find trusted local help, offer services, discover activities and help people nearby through one warm local network.',
          textAlign: isWide ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: isWide ? 21 : 17,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: isWide ? WrapAlignment.start : WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            _PrimaryButton(
              label: 'Create your account',
              onTap: onCreateAccount,
            ),
            _SecondaryButton(label: 'Explore LocalLink', onTap: onExplore),
            _SecondaryButton(
              label: 'I already have an account',
              onTap: onSignIn,
            ),
          ],
        ),
      ],
    );

    final preview = _HomePreviewCard(isWide: isWide);

    if (!isWide) {
      return Column(children: [text, const SizedBox(height: 30), preview]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 11, child: text),
        const SizedBox(width: 46),
        Expanded(flex: 9, child: preview),
      ],
    );
  }
}

class _HomePreviewCard extends StatelessWidget {
  const _HomePreviewCard({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
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
        padding: EdgeInsets.all(isWide ? 26 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nearby now',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            const _PreviewRow(
              color: AppColors.serviceGreen,
              icon: Icons.handshake_outlined,
              title: 'Find a service',
              subtitle: 'Local providers and available times',
            ),
            const _PreviewRow(
              color: AppColors.activityBlue,
              icon: Icons.event_available_outlined,
              title: 'Activities',
              subtitle: 'Things happening around you',
            ),
            const _PreviewRow(
              color: AppColors.primary,
              icon: Icons.volunteer_activism_outlined,
              title: 'Community Help',
              subtitle: 'Lost pets and property',
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionsGrid extends StatelessWidget {
  const _PrimaryActionsGrid({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final actions = [
      const _ActionCard(
        title: 'Find a service',
        subtitle: 'Ask local providers or book available time.',
        icon: Icons.search_rounded,
        color: AppColors.serviceGreen,
        path: '/services',
      ),
      const _ActionCard(
        title: 'Offer a service',
        subtitle: 'Create a local presence and receive enquiries.',
        icon: Icons.storefront_outlined,
        color: AppColors.primary,
        path: '/businesses',
      ),
      const _ActionCard(
        title: 'Activities',
        subtitle: 'Discover social, family and local events.',
        icon: Icons.groups_2_outlined,
        color: AppColors.activityBlue,
        path: '/opportunities',
      ),
      const _ActionCard(
        title: 'Community Help',
        subtitle: 'Lost pets and property nearby.',
        icon: Icons.volunteer_activism_outlined,
        color: AppColors.primary,
        path: '/community-help',
      ),
    ];

    return GridView.count(
      crossAxisCount: isWide ? 4 : 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: isWide ? 1.05 : 3.4,
      children: actions,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.path,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: () => launchUrl(Uri(path: path), webOnlyWindowName: '_self'),
        borderRadius: BorderRadius.circular(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxHeight < 170;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: isCompact
                  ? Row(
                      children: [
                        Icon(icon, color: color, size: 30),
                        const SizedBox(width: 16),
                        Expanded(child: _ActionCardCopy(title, subtitle)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, color: color, size: 30),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.charcoal,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _ActionCardCopy extends StatelessWidget {
  const _ActionCardCopy(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 21,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category});

  final PublicLandingCategory category;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(category.icon, color: category.color, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.title,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  category.description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return _SplitSection(
      isWide: isWide,
      title: 'Local discovery',
      subtitle:
          'LocalLink brings together activities, practical help, service providers and spare availability without turning the website into a public data dump.',
      children: const [
        _MiniFeature(
          title: 'Services',
          subtitle: 'Find nearby help and enquire through LocalLink.',
          color: AppColors.serviceGreen,
        ),
        _MiniFeature(
          title: 'Activities',
          subtitle: 'See social and community opportunities.',
          color: AppColors.activityBlue,
        ),
        _MiniFeature(
          title: 'Availability',
          subtitle: 'Discover genuine local time that providers share.',
          color: AppColors.primary,
        ),
      ],
    );
  }
}

class _CommunityHelpSection extends StatelessWidget {
  const _CommunityHelpSection({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return _SplitSection(
      isWide: isWide,
      title: 'Community Help',
      subtitle:
          'Post or follow lost pets and found property. Public shared links show limited preview information; the live post stays authoritative in LocalLink.',
      children: const [
        _MiniFeature(
          title: 'Lost and found',
          subtitle: 'Help people nearby keep a lookout.',
          color: AppColors.primary,
        ),
        _MiniFeature(
          title: 'Found property',
          subtitle: 'Keep identifying details private until claimed.',
          color: AppColors.success,
        ),
      ],
    );
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      child: Flex(
        direction: isWide ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveFlexChild(
            isExpanded: isWide,
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'For local businesses',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.06,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Create a simple LocalLink presence, list services, share available times and receive enquiries or bookings from nearby customers.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: isWide ? 30 : 0, height: isWide ? 0 : 22),
          _ResponsiveFlexChild(
            isExpanded: isWide,
            flex: 1,
            child: const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _BusinessChip(label: 'List services'),
                _BusinessChip(label: 'Share availability'),
                _BusinessChip(label: 'Receive enquiries'),
                _BusinessChip(label: 'Manage bookings'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSection extends StatelessWidget {
  const _AppSection({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use LocalLink where local life happens',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sign in to post, message, follow alerts, manage bookings and open shared links in the app.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(label: 'Sign in to LocalLink', onTap: onSignIn),
        ],
      ),
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.isWide,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final bool isWide;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      child: Flex(
        direction: isWide ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveFlexChild(
            isExpanded: isWide,
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.06,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: isWide ? 32 : 0, height: isWide ? 0 : 22),
          _ResponsiveFlexChild(
            isExpanded: isWide,
            flex: 6,
            child: Wrap(spacing: 12, runSpacing: 12, children: children),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveFlexChild extends StatelessWidget {
  const _ResponsiveFlexChild({
    required this.isExpanded,
    required this.flex,
    required this.child,
  });

  final bool isExpanded;
  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isExpanded) return child;
    return Expanded(flex: flex, child: child);
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

class _MiniFeature extends StatelessWidget {
  const _MiniFeature({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessChip extends StatelessWidget {
  const _BusinessChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.charcoal,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_forward_rounded),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.buttonPrimary,
        foregroundColor: AppColors.buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.charcoal,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
      child: Text(label),
    );
  }
}

class _PublicFooter extends StatelessWidget {
  const _PublicFooter();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 8,
      children: const [
        _FooterLink(label: 'Privacy', path: '/privacy'),
        _FooterLink(label: 'Terms', path: '/terms'),
        _FooterLink(label: 'Contact', path: '/contact'),
        _FooterLink(label: 'Delete account', path: '/delete-account'),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => launchUrl(Uri(path: path), webOnlyWindowName: '_self'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textLight,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}

enum PublicLandingCategory {
  communityHelp(
    path: 'community-help',
    title: 'Community Help',
    description:
        'Lost and found posts for missing pets and property. Open a shared post link for its latest public preview.',
    icon: Icons.volunteer_activism_outlined,
    color: AppColors.primary,
  ),
  opportunities(
    path: 'opportunities',
    title: 'Activities nearby',
    description:
        'Discover local activities and community opportunities. Shared activity links open the exact public preview when available.',
    icon: Icons.groups_2_outlined,
    color: AppColors.activityBlue,
  ),
  availability(
    path: 'availability',
    title: 'Available local time',
    description:
        'Find time-sensitive service availability from nearby providers. Exact shared availability links remain live previews.',
    icon: Icons.schedule_rounded,
    color: AppColors.primary,
  ),
  businesses(
    path: 'businesses',
    title: 'Local businesses',
    description:
        'Local providers can create a simple presence, list services, share availability and receive enquiries.',
    icon: Icons.storefront_outlined,
    color: AppColors.serviceGreen,
  ),
  services(
    path: 'services',
    title: 'Find a service',
    description:
        'Search for trusted local help, from practical jobs to specialist services, then enquire or book through LocalLink.',
    icon: Icons.handshake_outlined,
    color: AppColors.serviceGreen,
  );

  const PublicLandingCategory({
    required this.path,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String path;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  static PublicLandingCategory? fromPath(String path) {
    for (final category in values) {
      if (category.path == path) return category;
    }
    return null;
  }
}
