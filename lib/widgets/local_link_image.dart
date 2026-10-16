import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

class LocalLinkImage extends StatelessWidget {
  final String? imageUrl;
  final double aspectRatio;
  final IconData fallbackIcon;
  final Color accentColor;
  final String? semanticLabel;

  const LocalLinkImage({
    super.key,
    this.imageUrl,
    this.aspectRatio = 4 / 3,
    this.fallbackIcon = Icons.image_outlined,
    this.accentColor = AppColors.primary,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final source = imageUrl?.trim() ?? '';
    return Semantics(
      image: true,
      label: semanticLabel,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          child: source.isEmpty
              ? _Fallback(icon: fallbackIcon, accentColor: accentColor)
              : _ResolvedNetworkImage(
                  source: source,
                  fallbackIcon: fallbackIcon,
                  accentColor: accentColor,
                ),
        ),
      ),
    );
  }
}

class _ResolvedNetworkImage extends StatelessWidget {
  const _ResolvedNetworkImage({
    required this.source,
    required this.fallbackIcon,
    required this.accentColor,
  });

  final String source;
  final IconData fallbackIcon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final webUrl = _asDisplayableUrl(source);
    if (webUrl != null) {
      return _NetworkImageWithFallback(
        url: webUrl,
        fallbackIcon: fallbackIcon,
        accentColor: accentColor,
      );
    }

    final storageReference = _storageReference(source);
    if (storageReference == null) {
      return _Fallback(icon: fallbackIcon, accentColor: accentColor);
    }

    return FutureBuilder<String>(
      future: storageReference.getDownloadURL(),
      builder: (context, snapshot) {
        final resolvedUrl = snapshot.data?.trim() ?? '';
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _Fallback(icon: fallbackIcon, accentColor: accentColor);
        }
        if (snapshot.hasError || resolvedUrl.isEmpty) {
          return _Fallback(icon: fallbackIcon, accentColor: accentColor);
        }
        return _NetworkImageWithFallback(
          url: resolvedUrl,
          fallbackIcon: fallbackIcon,
          accentColor: accentColor,
        );
      },
    );
  }

  static String? _asDisplayableUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri.toString();
  }

  static Reference? _storageReference(String value) {
    try {
      if (value.startsWith('gs://')) {
        return FirebaseStorage.instance.refFromURL(value);
      }

      final looksLikeStoragePath =
          !value.contains('://') &&
          RegExp(
            r'^(businessPhotos|servicePhotos|organisationPhotos|organisationGroupPhotos|opportunityPhotos|communityHelpPhotos|profile_photos)/',
          ).hasMatch(value);
      if (looksLikeStoragePath) {
        return FirebaseStorage.instance.ref(value);
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

class _NetworkImageWithFallback extends StatelessWidget {
  const _NetworkImageWithFallback({
    required this.url,
    required this.fallbackIcon,
    required this.accentColor,
  });

  final String url;
  final IconData fallbackIcon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.fallback
          : WebHtmlElementStrategy.never,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return AnimatedOpacity(
            opacity: 1,
            duration: LocalLinkMotion.standard,
            curve: LocalLinkMotion.curve,
            child: child,
          );
        }
        return _Fallback(icon: fallbackIcon, accentColor: accentColor);
      },
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          final uri = Uri.tryParse(url);
          final safeUrl = uri == null
              ? '<invalid>'
              : uri.replace(query: '').toString();
          debugPrint('LocalLinkImage failed to load $safeUrl: $error');
        }
        return _Fallback(icon: fallbackIcon, accentColor: accentColor);
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  final IconData icon;
  final Color accentColor;

  const _Fallback({required this.icon, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: Center(child: Icon(icon, color: accentColor, size: 30)),
    );
  }
}
