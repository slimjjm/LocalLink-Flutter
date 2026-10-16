import 'package:cloud_firestore/cloud_firestore.dart';

class OrganisationGroup {
  const OrganisationGroup({
    required this.id,
    required this.organisationId,
    required this.name,
    required this.description,
    required this.displayType,
    required this.category,
    required this.subcategory,
    required this.ageLabel,
    required this.leaderUserIds,
    required this.isActive,
    required this.visibility,
    required this.membershipMode,
    required this.memberCount,
    required this.createdBy,
    required this.updatedBy,
    this.imageUrl = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String organisationId;
  final String name;
  final String description;
  final String displayType;
  final String category;
  final String subcategory;
  final String ageLabel;
  final List<String> leaderUserIds;
  final bool isActive;
  final String visibility;
  final String membershipMode;
  final int memberCount;
  final String createdBy;
  final String updatedBy;
  final String imageUrl;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  bool get isPublic => visibility == 'public';
  bool get isOpenMembership => membershipMode == 'open' && isPublic;
  bool get requiresApproval => membershipMode == 'approval_required';
  bool get isInviteOnly =>
      membershipMode == 'invite_only' ||
      (!isPublic && membershipMode == 'open');

  bool isLedBy(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return leaderUserIds.contains(uid);
  }

  factory OrganisationGroup.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return OrganisationGroup.fromMap(
      doc.id,
      doc.reference.parent.parent!.id,
      doc.data() ?? const {},
    );
  }

  factory OrganisationGroup.fromMap(
    String id,
    String organisationId,
    Map<String, dynamic> data,
  ) {
    return OrganisationGroup(
      id: id,
      organisationId: organisationId,
      name: _text(data['name']),
      description: _text(data['description']),
      displayType: _text(data['displayType'], fallback: 'group'),
      category: _text(data['category']),
      subcategory: _text(data['subcategory']),
      ageLabel: _text(data['ageLabel']),
      leaderUserIds: _stringList(data['leaderUserIds']),
      isActive: data['isActive'] != false,
      visibility: _text(data['visibility'], fallback: 'private'),
      membershipMode: _text(data['membershipMode'], fallback: 'open'),
      memberCount: _int(data['memberCount']),
      createdBy: _text(data['createdBy']),
      updatedBy: _text(data['updatedBy']),
      imageUrl: _text(data['imageUrl']),
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null,
    );
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class OrganisationMembership {
  const OrganisationMembership({
    required this.userId,
    required this.userName,
    required this.status,
    required this.role,
    required this.groupIds,
    this.createdAt,
    this.updatedAt,
  });

  final String userId;
  final String userName;
  final String status;
  final String role;
  final List<String> groupIds;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  bool get isActive => status == 'active';

  factory OrganisationMembership.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return OrganisationMembership(
      userId: _text(data['userId'], fallback: doc.id),
      userName: _text(data['userName'], fallback: 'LocalLink member'),
      status: _text(data['status'], fallback: 'active'),
      role: _text(data['role'], fallback: 'member'),
      groupIds: _stringList(data['groupIds']),
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null,
    );
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
