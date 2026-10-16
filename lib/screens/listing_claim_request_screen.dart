import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

class ListingClaimRequestScreen extends StatefulWidget {
  const ListingClaimRequestScreen({
    super.key,
    required this.listingType,
    required this.listingId,
    required this.listingTitle,
  });

  final String listingType;
  final String listingId;
  final String listingTitle;

  @override
  State<ListingClaimRequestScreen> createState() =>
      _ListingClaimRequestScreenState();
}

class _ListingClaimRequestScreenState extends State<ListingClaimRequestScreen> {
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _evidenceController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _evidenceController.dispose();
    super.dispose();
  }

  Future<void> _submitClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    if (_nameController.text.trim().isEmpty ||
        _relationshipController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add your name and relationship.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final existing = await FirebaseFirestore.instance
          .collection('listingClaims')
          .where('claimantUserId', isEqualTo: user.uid)
          .limit(50)
          .get();
      final alreadySubmitted = existing.docs.any((doc) {
        final data = doc.data();
        return data['listingType'] == widget.listingType &&
            data['listingId'] == widget.listingId &&
            (data['status'] == 'pending' || data['status'] == 'approved');
      });
      if (alreadySubmitted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have a claim for this listing.'),
          ),
        );
        return;
      }

      await LocalLinkAnalytics.instance.logEvent('business_claim_started', {
        'source': 'listing_claim_request',
        'listing_type': widget.listingType,
      });

      await FirebaseFirestore.instance.collection('listingClaims').add({
        'listingType': widget.listingType,
        'listingId': widget.listingId,
        'listingTitle': widget.listingTitle,
        'claimantUserId': user.uid,
        'claimantEmail': user.email ?? '',
        'claimantName': _nameController.text.trim(),
        'relationship': _relationshipController.text.trim(),
        'businessEmail': _emailController.text.trim(),
        'businessPhone': _phoneController.text.trim(),
        'website': _websiteController.text.trim(),
        'evidence': _evidenceController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await LocalLinkAnalytics.instance.logEvent('business_claim_completed', {
        'source': 'listing_claim_request',
        'listing_type': widget.listingType,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim request sent for review.')),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Listing claim request failed: $error');
        debugPrint('$stackTrace');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim request could not be sent.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = switch (widget.listingType) {
      'business' => 'business',
      'organisation' => 'organisation',
      'community_help_missing_pet' => 'missing pet post',
      _ => 'event',
    };
    final isMissingPetClaim =
        widget.listingType == 'community_help_missing_pet';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Claim this $noun'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMissingPetClaim
                      ? 'Community-added missing pet'
                      : 'Unclaimed listing',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.listingTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.charcoal,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isMissingPetClaim
                      ? 'Tell LocalLink why this is your pet. A moderator will review the claim before you can manage the post.'
                      : 'Tell LocalLink how you are connected to this $noun. A moderator will review it before ownership changes.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship',
                    hintText: 'Owner, manager, organiser...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: isMissingPetClaim
                        ? 'Best contact email'
                        : 'Contact email',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: isMissingPetClaim
                        ? 'Best contact phone'
                        : 'Contact phone',
                  ),
                ),
                if (!isMissingPetClaim) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _websiteController,
                    decoration: const InputDecoration(labelText: 'Website'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _evidenceController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: isMissingPetClaim
                        ? 'Verification details'
                        : 'Explanation or evidence',
                    hintText: isMissingPetClaim
                        ? 'Add details a moderator can use, such as microchip status, distinctive markings, missing poster link, vet contact, or other proof.'
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _submitClaim,
                    child: Text(_saving ? 'Sending...' : 'Send claim request'),
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
