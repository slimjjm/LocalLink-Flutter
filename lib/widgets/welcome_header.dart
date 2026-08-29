import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../screens/notifications_screen.dart';

import 'header_icon_button.dart';

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              _greeting(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 26,
                height: 1.05,
                fontWeight: FontWeight.w900,
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      );
    }

    final photoUrl = user.photoURL;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
          onBackgroundImageError: photoUrl == null
              ? null
              : (exception, stackTrace) {},
          child: photoUrl == null
              ? const Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primary,
                )
              : null,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            _greeting(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: AppColors.charcoal,
            ),
          ),
        ),
        const SizedBox(width: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('notifications')
              .where('isRead', isEqualTo: false)
              .snapshots(),
          builder: (context, snapshot) {
            final unread = snapshot.data?.docs.length ?? 0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                HeaderIconButton(
                  icon: Icons.notifications_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
                if (unread > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _Badge(
                      text: unread > 99 ? '99+' : unread.toString(),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;

  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
