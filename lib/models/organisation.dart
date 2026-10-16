import 'package:cloud_firestore/cloud_firestore.dart';

class Organisation {
  const Organisation({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.subcategories,
    required this.area,
    required this.publicLocation,
    required this.location,
    required this.phone,
    required this.email,
    required this.website,
    required this.imageUrl,
    required this.ownerId,
    required this.adminUserIds,
    required this.createdByModerator,
    required this.claimStatus,
    required this.listingOwnershipStatus,
    required this.isActive,
    required this.capabilities,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String category;
  final List<String> subcategories;
  final String area;
  final String publicLocation;
  final String location;
  final String phone;
  final String email;
  final String website;
  final String imageUrl;
  final String ownerId;
  final List<String> adminUserIds;
  final bool createdByModerator;
  final String claimStatus;
  final String listingOwnershipStatus;
  final bool isActive;
  final OrganisationCapabilities capabilities;
  final double? latitude;
  final double? longitude;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  bool get isClaimed =>
      listingOwnershipStatus == 'claimed' || claimStatus == 'approved';

  bool isManagedBy(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return ownerId == uid || adminUserIds.contains(uid);
  }

  factory Organisation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return Organisation.fromMap(doc.id, doc.data() ?? const {});
  }

  factory Organisation.fromMap(String id, Map<String, dynamic> data) {
    return Organisation(
      id: id,
      name: _text(data['name']),
      description: _text(data['description']),
      category: _text(data['category']),
      subcategories: _stringList(data['subcategories']),
      area: _text(data['area']),
      publicLocation: _text(data['publicLocation']),
      location: _text(data['location']),
      phone: _text(data['phone']),
      email: _text(data['email']),
      website: _text(data['website']),
      imageUrl: _text(data['imageUrl']),
      ownerId: _text(data['ownerId']),
      adminUserIds: _stringList(data['adminUserIds']),
      createdByModerator: data['createdByModerator'] == true,
      claimStatus: _text(data['claimStatus']),
      listingOwnershipStatus: _text(data['listingOwnershipStatus']),
      isActive: data['isActive'] != false,
      capabilities: OrganisationCapabilities.fromMap(
        data['capabilities'],
        category: _text(data['category']),
        subcategories: _stringList(data['subcategories']),
        name: _text(data['name']),
      ),
      latitude: _number(data['latitude']),
      longitude: _number(data['longitude']),
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null,
    );
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static List<String> _stringList(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class OrganisationCapabilities {
  const OrganisationCapabilities({
    required this.groups,
    required this.sessions,
    required this.fixtures,
  });

  final bool groups;
  final bool sessions;
  final bool fixtures;

  Map<String, bool> toMap() => {
    'groups': groups,
    'sessions': sessions,
    'fixtures': fixtures,
  };

  factory OrganisationCapabilities.fromMap(
    Object? value, {
    String category = '',
    List<String> subcategories = const [],
    String name = '',
  }) {
    final defaults = defaultsFor(
      category: category,
      subcategories: subcategories,
      name: name,
    );
    if (value is! Map) return defaults;

    return OrganisationCapabilities(
      groups: _bool(value['groups'], defaults.groups),
      sessions: _bool(value['sessions'], defaults.sessions),
      fixtures: _bool(value['fixtures'], defaults.fixtures),
    );
  }

  static OrganisationCapabilities defaultsFor({
    required String category,
    List<String> subcategories = const [],
    String name = '',
  }) {
    final text = [category, ...subcategories, name].join(' ').toLowerCase();
    final sportsLike = [
      'football',
      'rugby',
      'cricket',
      'hockey',
      'netball',
      'basketball',
      'tennis',
    ].any(text.contains);

    return OrganisationCapabilities(
      groups: true,
      sessions: true,
      fixtures: sportsLike,
    );
  }

  static bool _bool(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }
}
