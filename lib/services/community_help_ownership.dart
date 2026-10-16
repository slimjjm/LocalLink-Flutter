String? resolveCommunityHelpOwnerId(Map<String, dynamic> post) {
  final createdBy = post['createdBy']?.toString().trim() ?? '';
  final communityAdded = post['communityAdded'] == true;

  if (!communityAdded) {
    return createdBy.isEmpty ? null : createdBy;
  }

  final ownerId = post['ownerId']?.toString().trim() ?? '';
  final approved = post['claimStatus']?.toString().trim() == 'approved';
  return approved && ownerId.isNotEmpty ? ownerId : null;
}

bool isCommunityAddedMissingPet(Map<String, dynamic> post) {
  final type = post['type']?.toString().trim() ?? '';
  final mode = post['mode']?.toString().trim() ?? '';
  final category = post['itemCategory']?.toString().trim().toLowerCase() ?? '';
  return post['communityAdded'] == true &&
      type == 'lost_found' &&
      mode == 'lost' &&
      category == 'pet';
}

bool canClaimCommunityAddedMissingPet(Map<String, dynamic> post) {
  if (!isCommunityAddedMissingPet(post)) return false;
  final status = post['status']?.toString().trim() ?? '';
  final claimStatus = post['claimStatus']?.toString().trim() ?? 'unclaimed';
  final ownerId = post['ownerId']?.toString().trim() ?? '';
  final isRemoved = post['moderationStatus']?.toString().trim() == 'removed';
  final isResolved = status == 'resolved' || post['resolvedAt'] != null;

  return post['isActive'] == true &&
      !isRemoved &&
      !isResolved &&
      ownerId.isEmpty &&
      (claimStatus.isEmpty || claimStatus == 'unclaimed');
}
