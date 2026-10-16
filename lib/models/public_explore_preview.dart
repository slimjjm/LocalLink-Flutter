class PublicExplorePreview {
  const PublicExplorePreview({
    required this.type,
    required this.id,
    this.parentId = '',
    required this.label,
    required this.title,
    this.subtitle = '',
    this.location = '',
    this.imageUrl = '',
  });

  final String type;
  final String id;
  final String parentId;
  final String label;
  final String title;
  final String subtitle;
  final String location;
  final String imageUrl;

  bool get hasImage => imageUrl.trim().isNotEmpty;

  Uri? get publicUri {
    if (id.trim().isEmpty) return null;

    switch (type) {
      case 'communityHelp':
        return Uri(path: '/community-help/$id');
      case 'activity':
      case 'opportunity':
        return Uri(path: '/opportunities/$id');
      case 'availability':
        return Uri(path: '/availability/$id');
      case 'business':
        return Uri(path: '/businesses/$id');
      case 'service':
        if (parentId.trim().isEmpty) return null;
        return Uri(path: '/services/$parentId/$id');
    }

    return null;
  }

  factory PublicExplorePreview.fromData(Map<String, dynamic> data) {
    return PublicExplorePreview(
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

class PublicExploreRoute {
  const PublicExploreRoute({this.area = ''});

  final String area;

  static PublicExploreRoute? fromUri(Uri uri) {
    final segments = uri.pathSegments
        .map(Uri.decodeComponent)
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (segments.isEmpty || segments.first != 'explore') return null;
    if (segments.length == 1) return const PublicExploreRoute();

    return PublicExploreRoute(area: segments[1]);
  }
}
