import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/deep_link_service.dart';
import '../theme/app_colors.dart';

class PublicSharedItemScreen extends StatefulWidget {
  const PublicSharedItemScreen({super.key, required this.target});

  final LocalLinkDeepLinkTarget target;

  static Widget? fromUri({required Uri uri}) {
    final target = LocalLinkDeepLinkTarget.fromUri(uri);
    if (target == null) return null;
    return PublicSharedItemScreen(target: target);
  }

  @override
  State<PublicSharedItemScreen> createState() => _PublicSharedItemScreenState();
}

class _PublicSharedItemScreenState extends State<PublicSharedItemScreen> {
  late final Future<_PublicSharePreview> _previewFuture = _loadPreview();

  Future<_PublicSharePreview> _loadPreview() async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('getPublicSharePreview')
        .call({
          'type': widget.target.type.name,
          'id': widget.target.id,
          'parentId': widget.target.parentId,
        });

    return _PublicSharePreview.fromData(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = Uri.base.path;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: FutureBuilder<_PublicSharePreview>(
              future: _previewFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _PublicShell(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return _PublicShell(
                    child: _FallbackContent(
                      title: 'Open this LocalLink post',
                      message:
                          'This shared link points to LocalLink. Open it in the app for the latest details.',
                      path: path,
                    ),
                  );
                }

                return _PublicShell(
                  child: _PreviewContent(preview: snapshot.data!, path: path),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.preview, required this.path});

  final _PublicSharePreview preview;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preview.imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.network(
              preview.imageUrl,
              width: double.infinity,
              height: 260,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        if (preview.imageUrl.isNotEmpty) const SizedBox(height: 22),
        Text(
          preview.label,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          preview.title,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 34,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (preview.subtitle.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            preview.subtitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (preview.location.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.place_outlined, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview.location,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: () => _openNativeApp(context),
          icon: const Icon(Icons.phone_iphone_rounded),
          label: const Text('Open in LocalLink'),
        ),
        const SizedBox(height: 12),
        Text(
          'Latest details are available in the LocalLink app. This web preview only shows public information.',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          'locallinkapp.co.uk$path',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _openNativeApp(BuildContext context) async {
    final appUri = preview.appUri;
    if (appUri == null) return;

    try {
      final opened = await launchUrl(appUri, webOnlyWindowName: '_self');
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open the LocalLink app to continue.')),
    );
  }
}

class _FallbackContent extends StatelessWidget {
  const _FallbackContent({
    required this.title,
    required this.message,
    required this.path,
  });

  final String title;
  final String message;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.link_rounded, color: AppColors.primary, size: 40),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        SelectableText(
          'locallinkapp.co.uk$path',
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _PublicShell extends StatelessWidget {
  const _PublicShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('icons/Icon-192.png', width: 34, height: 34),
              const SizedBox(width: 10),
              const Text(
                'LocalLink',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ],
      ),
    );
  }
}

class _PublicSharePreview {
  const _PublicSharePreview({
    required this.type,
    required this.id,
    required this.parentId,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.imageUrl,
  });

  final String type;
  final String id;
  final String parentId;
  final String label;
  final String title;
  final String subtitle;
  final String location;
  final String imageUrl;

  Uri? get appUri {
    if (id.isEmpty) return null;

    switch (type) {
      case 'communityHelp':
        return Uri(scheme: 'locallink', host: 'community-help', path: '/$id');
      case 'activity':
        return Uri(scheme: 'locallink', host: 'opportunity', path: '/$id');
      case 'availability':
        return Uri(scheme: 'locallink', host: 'availability', path: '/$id');
      case 'business':
        return Uri(scheme: 'locallink', host: 'business', path: '/$id');
      case 'service':
        if (parentId.isEmpty) return null;
        return Uri(
          scheme: 'locallink',
          host: 'business',
          path: '/$parentId',
          queryParameters: {'serviceId': id},
        );
    }

    return null;
  }

  factory _PublicSharePreview.fromData(Map<String, dynamic> data) {
    return _PublicSharePreview(
      type: data['type']?.toString() ?? '',
      id: data['id']?.toString() ?? '',
      parentId: data['parentId']?.toString() ?? '',
      label: data['label']?.toString() ?? 'LocalLink',
      title: data['title']?.toString() ?? 'LocalLink post',
      subtitle: data['subtitle']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
      imageUrl: data['imageUrl']?.toString() ?? '',
    );
  }
}
