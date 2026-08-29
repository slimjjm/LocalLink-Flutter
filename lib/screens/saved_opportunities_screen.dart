import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'business_detail_screen.dart';
import 'opportunity_detail_screen.dart';

class SavedOpportunitiesScreen extends StatelessWidget {
  const SavedOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Saved'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SavedBusinessesSection(uid: uid),
          const SizedBox(height: 26),
          _SavedActivitySection(uid: uid),
        ],
      ),
    );
  }
}

class _SavedBusinessesSection extends StatelessWidget {
  const _SavedBusinessesSection({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('savedBusinesses')
          .orderBy('savedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return _SavedSection(
          title: 'Saved Pages',
          emptyText: 'Pages you save will appear here.',
          isLoading: !snapshot.hasData,
          hasError: snapshot.hasError,
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final businessId = data['businessId']?.toString() ?? doc.id;
            final name = data['businessName']?.toString() ?? 'Page';
            final category = data['category']?.toString() ?? 'Service';

            return _SavedTile(
              icon: Icons.storefront_outlined,
              accentColor: AppColors.serviceGreen,
              title: name,
              subtitle: category,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BusinessDetailScreen(businessId: businessId),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _SavedActivitySection extends StatelessWidget {
  const _SavedActivitySection({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('savedOpportunities')
          .orderBy('savedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return _SavedSection(
          title: 'Saved activities & services',
          emptyText: 'Saved activities and services will appear here.',
          isLoading: !snapshot.hasData,
          hasError: snapshot.hasError,
          children: docs.map((savedDoc) {
            final data = savedDoc.data() as Map<String, dynamic>;
            final opportunityId = data['opportunityId']?.toString();

            if (opportunityId == null || opportunityId.isEmpty) {
              return const SizedBox.shrink();
            }

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('opportunities')
                  .doc(opportunityId)
                  .get(),
              builder: (context, oppSnapshot) {
                if (!oppSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  );
                }

                if (!oppSnapshot.data!.exists) {
                  return const SizedBox.shrink();
                }

                final opportunity =
                    oppSnapshot.data!.data() as Map<String, dynamic>;
                final title = opportunity['title']?.toString() ?? 'Activity';
                final category = opportunity['category']?.toString() ?? '';
                final location = opportunity['location']?.toString() ?? '';
                final type = opportunity['type']?.toString() ?? 'activity';
                final isService = type == 'service';

                return _SavedTile(
                  icon: isService
                      ? Icons.handshake_outlined
                      : Icons.groups_2_outlined,
                  accentColor: isService
                      ? AppColors.serviceGreen
                      : AppColors.primary,
                  title: title,
                  subtitle: [
                    if (category.isNotEmpty) category,
                    if (location.isNotEmpty) location,
                  ].join(' • '),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OpportunityDetailScreen(
                          opportunityId: opportunityId,
                          opportunity: opportunity,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _SavedSection extends StatelessWidget {
  const _SavedSection({
    required this.title,
    required this.emptyText,
    required this.isLoading,
    required this.hasError,
    required this.children,
  });

  final String title;
  final String emptyText;
  final bool isLoading;
  final bool hasError;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (hasError)
          const _SavedEmptyCard(text: 'Saved items could not be loaded.')
        else if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          )
        else if (children.isEmpty)
          _SavedEmptyCard(text: emptyText)
        else
          ...children,
      ],
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: 0.10),
          child: Icon(icon, color: accentColor),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _SavedEmptyCard extends StatelessWidget {
  const _SavedEmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
