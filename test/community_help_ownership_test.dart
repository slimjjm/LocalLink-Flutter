import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/community_help_ownership.dart';

void main() {
  test('legacy user-created post resolves createdBy as owner', () {
    expect(resolveCommunityHelpOwnerId({'createdBy': 'user-1'}), 'user-1');
  });

  test('community-added unclaimed missing pet has no operational owner', () {
    final post = {
      'createdBy': 'moderator-1',
      'communityAdded': true,
      'type': 'lost_found',
      'mode': 'lost',
      'itemCategory': 'Pet',
      'claimStatus': 'unclaimed',
      'isActive': true,
    };

    expect(resolveCommunityHelpOwnerId(post), isNull);
    expect(isCommunityAddedMissingPet(post), isTrue);
    expect(canClaimCommunityAddedMissingPet(post), isTrue);
  });

  test('approved community-added missing pet resolves ownerId as owner', () {
    final post = {
      'createdBy': 'moderator-1',
      'communityAdded': true,
      'type': 'lost_found',
      'mode': 'lost',
      'itemCategory': 'Pet',
      'claimStatus': 'approved',
      'ownerId': 'owner-1',
      'isActive': true,
    };

    expect(resolveCommunityHelpOwnerId(post), 'owner-1');
    expect(canClaimCommunityAddedMissingPet(post), isFalse);
  });

  test(
    'pending, resolved and removed community-added pets are not claimable',
    () {
      final base = {
        'communityAdded': true,
        'type': 'lost_found',
        'mode': 'lost',
        'itemCategory': 'Pet',
        'isActive': true,
      };

      expect(
        canClaimCommunityAddedMissingPet({...base, 'claimStatus': 'pending'}),
        isFalse,
      );
      expect(
        canClaimCommunityAddedMissingPet({...base, 'status': 'resolved'}),
        isFalse,
      );
      expect(
        canClaimCommunityAddedMissingPet({
          ...base,
          'moderationStatus': 'removed',
        }),
        isFalse,
      );
    },
  );
}
