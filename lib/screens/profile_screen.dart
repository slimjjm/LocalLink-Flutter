import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../services/review_service.dart';
import '../services/follow_service.dart';
import '../services/trust_safety_service.dart';
import '../widgets/report_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'followers_screen.dart';

import 'saved_opportunities_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? photoUrl;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.photoUrl,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;
  bool isFollowing = false;
  bool loadingFollow = true;

  final reviewService = ReviewService();

  final followService = FollowService();

  final trustSafetyService = TrustSafetyService();

  bool isBlocked = false;
  bool loadingBlock = true;

  Future<void> _changePhoto() async {
    final picker = ImagePicker();

    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _uploading = true;
    });

    try {
      final file = File(picked.path);

      final ref = FirebaseStorage.instance.ref().child(
        'profile_photos/${widget.userId}.jpg',
      );

      await ref.putFile(file);

      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({'photoUrl': url}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }

    if (mounted) {
      setState(() {
        _uploading = false;
      });
    }
  }

  Future<void> loadFollowStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('following')
        .doc(widget.userId)
        .get();

    if (!mounted) return;

    setState(() {
      isFollowing = doc.exists;
      loadingFollow = false;
    });
  }

  Future<void> loadBlockStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null || currentUser.uid == widget.userId) {
      if (mounted) {
        setState(() {
          loadingBlock = false;
        });
      }
      return;
    }

    final blocked = await trustSafetyService.isBlocked(
      currentUserId: currentUser.uid,
      blockedUserId: widget.userId,
    );

    if (!mounted) return;

    setState(() {
      isBlocked = blocked;
      loadingBlock = false;
    });
  }

  Future<void> _reportProfile() async {
    await showReportSheet(
      context: context,
      reportType: 'profile',
      targetId: widget.userId,
      targetPath: 'users/${widget.userId}',
      targetPreview: widget.userName,
      reportedUserId: widget.userId,
    );
  }

  Future<void> _blockUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to block this user.')),
      );
      return;
    }

    if (currentUser.uid == widget.userId || isBlocked || loadingBlock) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Block user?'),
          content: const Text(
            'They will be added to your blocked users list. You can still report anything that concerns you.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Block'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      loadingBlock = true;
    });

    await trustSafetyService.blockUser(
      currentUserId: currentUser.uid,
      blockedUserId: widget.userId,
      blockedUserName: widget.userName,
      blockedPhotoUrl: widget.photoUrl,
    );

    if (!mounted) return;

    setState(() {
      isBlocked = true;
      loadingBlock = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('User blocked. Thanks for helping keep LocalLink safe.'),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    loadFollowStatus();
    loadBlockStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (FirebaseAuth.instance.currentUser?.uid != widget.userId)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) async {
                if (value == 'report') {
                  await _reportProfile();
                }

                if (value == 'block') {
                  await _blockUser();
                }
              },
              itemBuilder: (context) {
                return [
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report profile'),
                  ),
                  PopupMenuItem(
                    value: 'block',
                    enabled: !isBlocked && !loadingBlock,
                    child: Text(isBlocked ? 'Blocked' : 'Block user'),
                  ),
                ];
              },
            ),
        ],
      ),
      body: FutureBuilder(
        future: Future.wait([
          FirebaseFirestore.instance
              .collection('opportunities')
              .where('createdBy', isEqualTo: widget.userId)
              .get(),

          FirebaseFirestore.instance
              .collectionGroup('attendees')
              .where('userId', isEqualTo: widget.userId)
              .get(),

          FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .get(),

          FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .collection('followers')
              .get(),

          FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .collection('following')
              .get(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(snapshot.error.toString()),
              ),
            );
          }

          final created = (snapshot.data![0] as QuerySnapshot).docs.length;

          final attended = (snapshot.data![1] as QuerySnapshot).docs.length;

          final createdDocs = (snapshot.data![0] as QuerySnapshot).docs;

          int hostedAttendees = 0;

          for (final doc in createdDocs) {
            final data = doc.data() as Map<String, dynamic>;

            hostedAttendees += (data['attendeeCount'] as int?) ?? 0;
          }

          final communityScore = (created * 10) + attended;

          final followerCount =
              (snapshot.data![3] as QuerySnapshot).docs.length;

          final followingCount =
              (snapshot.data![4] as QuerySnapshot).docs.length;

          final userDoc = snapshot.data![2] as DocumentSnapshot;

          final userData = userDoc.data() as Map<String, dynamic>? ?? {};
          final profilePhotoUrl =
              (userData['photoUrl']?.toString()) ?? widget.photoUrl;
          final bio = userData['bio']?.toString() ?? '';

          final reviewCount = (userData['reviewCount'] ?? 0) as int;

          final averageRating = ((userData['averageRating'] ?? 0) as num)
              .toDouble();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    profilePhotoUrl != null && profilePhotoUrl.isNotEmpty
                        ? CircleAvatar(
                            radius: 55,
                            backgroundImage: NetworkImage(profilePhotoUrl),
                          )
                        : CircleAvatar(
                            radius: 55,
                            child: Text(
                              (userData['userName']?.toString() ??
                                      widget.userName)
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),

                    GestureDetector(
                      onTap: _uploading ? null : _changePhoto,
                      child: CircleAvatar(
                        radius: 18,
                        child: _uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  userData['userName']?.toString() ?? widget.userName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (FirebaseAuth.instance.currentUser?.uid == widget.userId)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Profile'),
                    onPressed: () async {
                      final nameController = TextEditingController(
                        text: widget.userName,
                      );

                      final bioController = TextEditingController(text: bio);

                      final save = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Edit Profile'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Display Name',
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  TextField(
                                    controller: bioController,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: 'Bio',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context, false);
                                },
                                child: const Text('Cancel'),
                              ),

                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context, true);
                                },
                                child: const Text('Save'),
                              ),
                            ],
                          );
                        },
                      );

                      if (save != true) return;

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.userId)
                          .set({
                            'userName': nameController.text.trim(),
                            'bio': bioController.text.trim(),
                          }, SetOptions(merge: true));

                      if (!mounted) return;

                      setState(() {});

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated')),
                      );
                    },
                  ),
                const SizedBox(height: 12),
                if (FirebaseAuth.instance.currentUser?.uid == widget.userId)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.bookmark_border),
                      label: const Text('Saved Opportunities'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SavedOpportunitiesScreen(),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 12),
                FutureBuilder<User?>(
                  future: Future.value(FirebaseAuth.instance.currentUser),
                  builder: (context, snapshot) {
                    final currentUser = snapshot.data;

                    if (currentUser == null ||
                        currentUser.uid == widget.userId) {
                      return const SizedBox();
                    }

                    if (isBlocked) {
                      return SizedBox(
                        width: 180,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.block),
                          label: const Text('Blocked'),
                          onPressed: null,
                        ),
                      );
                    }

                    return SizedBox(
                      width: 180,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          isFollowing ? Icons.person_remove : Icons.person_add,
                        ),
                        label: Text(isFollowing ? 'Following' : 'Follow'),
                        onPressed: () async {
                          if (loadingFollow) {
                            return;
                          }

                          setState(() {
                            loadingFollow = true;
                          });

                          if (isFollowing) {
                            await followService.unfollowUser(
                              currentUserId: currentUser.uid,
                              targetUserId: widget.userId,
                            );
                          } else {
                            final currentUserDoc = await FirebaseFirestore
                                .instance
                                .collection('users')
                                .doc(currentUser.uid)
                                .get();

                            final currentUserData = currentUserDoc.data() ?? {};

                            await followService.followUser(
                              currentUserId: currentUser.uid,
                              currentUserName:
                                  currentUserData['userName']?.toString() ??
                                  currentUserData['name']?.toString() ??
                                  currentUser.displayName ??
                                  'User',
                              currentPhotoUrl: currentUserData['photoUrl']
                                  ?.toString(),
                              targetUserId: widget.userId,
                              targetUserName: widget.userName,
                              targetPhotoUrl: widget.photoUrl,
                            );
                          }
                          await loadFollowStatus();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),

                const Text(
                  'Community Member',
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 16),

                if (bio.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(bio),
                  ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                created.toString(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text('Created'),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                attended.toString(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text('Attended'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FollowersScreen(userId: widget.userId),
                            ),
                          );
                        },
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  followerCount.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text('Followers'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                followingCount.toString(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text('Following'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Community Stats',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 12),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.star),
                    title: const Text('Community Score'),
                    trailing: Text(communityScore.toString()),
                  ),
                ),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups),
                    title: const Text('Hosted Attendees'),
                    trailing: Text(hostedAttendees.toString()),
                  ),
                ),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('Opportunities Created'),
                    trailing: Text(created.toString()),
                  ),
                ),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle),
                    title: const Text('Opportunities Attended'),
                    trailing: Text(attended.toString()),
                  ),
                ),
                const SizedBox(height: 24),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Reviews',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 12),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: Text(
                      averageRating == 0
                          ? 'No reviews yet'
                          : averageRating.toStringAsFixed(1),
                    ),
                    subtitle: Text('$reviewCount reviews'),
                  ),
                ),

                StreamBuilder<QuerySnapshot>(
                  stream: reviewService.reviewsStream(widget.userId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox();
                    }

                    final reviews = snapshot.data!.docs;

                    if (reviews.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No reviews yet'),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: reviews.length,
                      itemBuilder: (context, index) {
                        final data =
                            reviews[index].data() as Map<String, dynamic>;

                        final rating = data['rating'] ?? 0;

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['reviewerName']?.toString() ?? 'User',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text('⭐' * rating),

                                const SizedBox(height: 6),

                                Text(data['text']?.toString() ?? ''),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 24),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Achievements',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (attended > 0)
                      const Chip(label: Text('🎉 Joined Event')),

                    if (created > 0) const Chip(label: Text('🏆 Organiser')),

                    if (created >= 5)
                      const Chip(label: Text('🔥 Community Builder')),

                    if (hostedAttendees >= 25)
                      const Chip(label: Text('👥 Crowd Puller')),

                    if (attended >= 10)
                      const Chip(label: Text('⭐ Active Member')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
