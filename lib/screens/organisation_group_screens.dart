import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../models/organisation_role.dart';
import '../services/organisation_service.dart';
import '../services/organisation_permissions.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_chip.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';
import 'create_opportunity_screen.dart';
import 'opportunity_detail_screen.dart';
import 'organisation_people_screen.dart';

const _membershipModes = ['open', 'approval_required', 'invite_only'];
const _displayTypes = ['group', 'team', 'section', 'class'];

String groupCollectionLabel(Organisation organisation, {bool plural = true}) {
  final text = [
    organisation.category,
    ...organisation.subcategories,
    organisation.name,
  ].join(' ').toLowerCase();

  if (text.contains('scout') ||
      text.contains('beaver') ||
      text.contains('cub')) {
    return plural ? 'Sections' : 'Section';
  }
  if (text.contains('dance') ||
      text.contains('ballet') ||
      text.contains('school')) {
    return plural ? 'Classes' : 'Class';
  }
  if (text.contains('rugby') ||
      text.contains('football') ||
      text.contains('cricket') ||
      text.contains('sport')) {
    return plural ? 'Teams' : 'Team';
  }
  return plural ? 'Groups' : 'Group';
}

String membershipModeLabel(String mode) {
  return switch (mode) {
    'approval_required' => 'Approval required',
    'invite_only' => 'Invite only',
    _ => 'Open',
  };
}

String normaliseMembershipMode(String mode) {
  return _membershipModes.contains(mode) ? mode : 'open';
}

@visibleForTesting
String groupEditorCategoryValue({
  required Organisation organisation,
  OrganisationGroup? group,
}) {
  final groupCategory = group?.category.trim() ?? '';
  return groupCategory.isNotEmpty ? groupCategory : organisation.category;
}

@visibleForTesting
List<String> groupLeaderDisplayNames({
  required OrganisationGroup group,
  required Iterable<OrganisationMembership> people,
}) {
  final leaderIds = group.leaderUserIds.toSet();
  final names = <String>[];
  for (final person in people) {
    final leadsThisGroup =
        leaderIds.contains(person.userId) ||
        (person.role == organisationRoleGroupLeader &&
            person.groupIds.contains(group.id));
    if (person.isActive &&
        leadsThisGroup &&
        person.userName.trim().isNotEmpty) {
      names.add(person.userName.trim());
    }
  }
  names.sort();
  return names;
}

String defaultMembershipModeFor({
  required String category,
  required String subcategory,
  required String ageLabel,
}) {
  final text = '$category $subcategory $ageLabel'.toLowerCase();
  if (text.contains('family') ||
      text.contains('child') ||
      text.contains('junior') ||
      text.contains('youth') ||
      text.contains('under ') ||
      text.contains('u8') ||
      text.contains('u10') ||
      text.contains('scout') ||
      text.contains('beaver') ||
      text.contains('cub')) {
    return 'approval_required';
  }
  return 'open';
}

class OrganisationGroupsScreen extends StatelessWidget {
  OrganisationGroupsScreen({super.key, required this.organisation})
    : _service = OrganisationService();

  final Organisation organisation;
  final OrganisationService _service;

  @override
  Widget build(BuildContext context) {
    final label = groupCollectionLabel(organisation);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(label),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          LocalLinkSurfaceCard(
            elevated: false,
            color: AppColors.activitySoft,
            padding: const EdgeInsets.all(LocalLinkSpacing.md),
            child: Row(
              children: [
                const LocalLinkIconBadge(
                  icon: Icons.apartment_rounded,
                  color: AppColors.activityBlue,
                  size: 42,
                ),
                const SizedBox(width: LocalLinkSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        organisation.name,
                        style: LocalLinkTextStyles.cardTitle,
                      ),
                      if (organisation.publicLocation.isNotEmpty) ...[
                        const SizedBox(height: LocalLinkSpacing.xxs),
                        Text(
                          organisation.publicLocation,
                          style: LocalLinkTextStyles.metadata,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          LocalLinkSectionHeader(
            title: label,
            subtitle: 'Teams, classes and sections that need their own people.',
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkButton(
            label:
                'Add ${groupCollectionLabel(organisation, plural: false).toLowerCase()}',
            icon: Icons.add_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    OrganisationGroupEditScreen(organisation: organisation),
              ),
            ),
            expand: true,
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          StreamBuilder<List<OrganisationGroup>>(
            stream: _service.watchGroups(organisation.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const LocalLinkErrorState(
                  title: 'Groups could not be loaded',
                  message: 'Please try again in a moment.',
                );
              }
              if (!snapshot.hasData) {
                return const LocalLinkLoadingState(label: 'Loading groups');
              }
              final groups = snapshot.data!;
              if (groups.isEmpty) {
                return LocalLinkEmptyState(
                  icon: Icons.groups_2_outlined,
                  title: 'No ${label.toLowerCase()} yet',
                  message:
                      'Add one when a team, class or section needs its own members.',
                );
              }
              return Column(
                children: groups
                    .map(
                      (group) => _GroupTile(
                        group: group,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrganisationGroupDetailScreen(
                              organisation: organisation,
                              groupId: group.id,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class OrganisationGroupEditScreen extends StatefulWidget {
  const OrganisationGroupEditScreen({
    super.key,
    required this.organisation,
    this.group,
  });

  final Organisation organisation;
  final OrganisationGroup? group;

  @override
  State<OrganisationGroupEditScreen> createState() =>
      _OrganisationGroupEditScreenState();
}

class _OrganisationGroupEditScreenState
    extends State<OrganisationGroupEditScreen> {
  final _service = OrganisationService();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ageLabelController;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _removeImage = false;
  late String _displayType;
  late String _membershipMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameController = TextEditingController(text: group?.name ?? '');
    _descriptionController = TextEditingController(
      text: group?.description ?? '',
    );
    _ageLabelController = TextEditingController(text: group?.ageLabel ?? '');
    _displayType =
        group?.displayType ?? _suggestDisplayType(widget.organisation);
    _membershipMode =
        group?.membershipMode ??
        defaultMembershipModeFor(
          category: widget.organisation.category,
          subcategory: '',
          ageLabel: '',
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _ageLabelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add a name.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final group = widget.group;
      String? imageUrl;
      if (_selectedImage != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null || user.isAnonymous) {
          throw StateError('Sign in required.');
        }
        final targetGroupId =
            group?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
        final ref = FirebaseStorage.instance.ref().child(
          'organisationGroupPhotos/${widget.organisation.id}/$targetGroupId/${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        final bytes = await _selectedImage!.readAsBytes();
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {
              'ownerId': user.uid,
              'organisationId': widget.organisation.id,
            },
          ),
        );
        imageUrl = await ref.getDownloadURL();
      } else if (_removeImage) {
        imageUrl = '';
      }

      final category = groupEditorCategoryValue(
        organisation: widget.organisation,
        group: group,
      );
      if (group == null) {
        final ref = await _service.createGroup(
          organisation: widget.organisation,
          name: name,
          description: _descriptionController.text,
          displayType: _displayType,
          category: category,
          subcategory: '',
          ageLabel: _ageLabelController.text,
          membershipMode: _membershipMode,
        );
        if (imageUrl != null) {
          final createdGroup =
              OrganisationGroup.fromMap(ref.id, widget.organisation.id, {
                'name': name,
                'description': _descriptionController.text,
                'displayType': _displayType,
                'category': category,
                'membershipMode': _membershipMode,
              });
          await _service.updateGroup(
            group: createdGroup,
            name: name,
            description: _descriptionController.text,
            displayType: _displayType,
            category: category,
            subcategory: '',
            ageLabel: _ageLabelController.text,
            membershipMode: _membershipMode,
            leaderUserIds: const [],
            imageUrl: imageUrl,
          );
        }
      } else {
        await _service.updateGroup(
          group: group,
          name: name,
          description: _descriptionController.text,
          displayType: _displayType,
          category: category,
          subcategory: group.subcategory,
          ageLabel: _ageLabelController.text,
          membershipMode: _membershipMode,
          leaderUserIds: group.leaderUserIds,
          imageUrl: imageUrl,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(group == null ? 'Group created.' : 'Group updated.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (image == null) return;
    setState(() {
      _selectedImage = image;
      _selectedImageBytes = null;
      _removeImage = false;
    });
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => _selectedImageBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final groupLabel = groupCollectionLabel(widget.organisation, plural: false);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.group == null ? 'Add $groupLabel' : 'Edit $groupLabel',
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          LocalLinkFormSection(
            title: '$groupLabel details',
            helperText: 'Add the details people need to recognise this.',
            children: [
              _GroupImageEditor(
                imageUrl: widget.group?.imageUrl ?? '',
                selectedImage: _selectedImage,
                selectedImageBytes: _selectedImageBytes,
                removeImage: _removeImage,
                onPick: _pickImage,
                onRemove:
                    (widget.group?.imageUrl.isNotEmpty == true ||
                        _selectedImage != null)
                    ? () => setState(() {
                        _selectedImage = null;
                        _selectedImageBytes = null;
                        _removeImage = true;
                      })
                    : null,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(controller: _nameController, label: 'Name'),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _descriptionController,
                label: 'Short description',
                maxLines: 3,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _ageLabelController,
                label: 'Age or level',
                hintText: 'Under 8s, Adults, Beginners',
              ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          LocalLinkFormSection(
            title: 'Setup',
            children: [
              Text('This is a...', style: LocalLinkTextStyles.label),
              const SizedBox(height: LocalLinkSpacing.xs),
              Wrap(
                spacing: LocalLinkSpacing.xs,
                runSpacing: LocalLinkSpacing.xs,
                children: _displayTypes
                    .map(
                      (type) => LocalLinkChip(
                        label: _titleCase(type),
                        selected: _displayType == type,
                        accentColor: AppColors.activityBlue,
                        onSelected: (_) => setState(() => _displayType = type),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: LocalLinkSpacing.md),
              Text('Joining', style: LocalLinkTextStyles.label),
              const SizedBox(height: LocalLinkSpacing.xs),
              Wrap(
                spacing: LocalLinkSpacing.xs,
                runSpacing: LocalLinkSpacing.xs,
                children: _membershipModes
                    .map(
                      (mode) => LocalLinkChip(
                        label: membershipModeLabel(mode),
                        selected: _membershipMode == mode,
                        accentColor: AppColors.activityBlue,
                        onSelected: (_) =>
                            setState(() => _membershipMode = mode),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          _GroupLeadersSection(
            organisation: widget.organisation,
            group: widget.group,
            service: _service,
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          LocalLinkButton(
            label: _saving ? 'Saving...' : 'Save',
            onPressed: _saving ? null : _save,
            isLoading: _saving,
            expand: true,
          ),
        ],
      ),
    );
  }

  static String _suggestDisplayType(Organisation organisation) {
    return groupCollectionLabel(organisation, plural: false).toLowerCase();
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class OrganisationGroupDetailScreen extends StatelessWidget {
  OrganisationGroupDetailScreen({
    super.key,
    required this.organisation,
    required this.groupId,
  }) : _service = OrganisationService();

  final Organisation organisation;
  final String groupId;
  final OrganisationService _service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _service.watchGroup(organisation.id, groupId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('This group could not be loaded.')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snapshot.data!;
        if (!doc.exists) {
          return const Scaffold(
            body: Center(child: Text('This group is no longer here.')),
          );
        }

        final group = OrganisationGroup.fromFirestore(doc);
        final uid = FirebaseAuth.instance.currentUser?.uid;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uid == null
              ? null
              : _service.watchOrganisationMembership(
                  organisationId: organisation.id,
                  userId: uid,
                ),
          builder: (context, roleSnapshot) {
            final roleData = roleSnapshot.data?.data();
            final organisationRole = roleData?['status'] == 'active'
                ? (roleData?['role']?.toString() ?? '')
                : '';
            final canManage = OrganisationPermissions.canManageGroup(
              organisation: organisation,
              group: group,
              uid: uid,
              organisationRole: organisationRole,
            );

            return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                title: Text(_titleCase(group.displayType)),
                backgroundColor: AppColors.background,
                foregroundColor: AppColors.charcoal,
                elevation: 0,
                actions: [
                  if (canManage)
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrganisationGroupEditScreen(
                            organisation: organisation,
                            group: group,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _GroupHeader(organisation: organisation, group: group),
                  const SizedBox(height: LocalLinkSpacing.md),
                  _MembershipCard(
                    organisation: organisation,
                    group: group,
                    service: _service,
                    canManage: canManage,
                  ),
                  if (canManage) ...[
                    const SizedBox(height: LocalLinkSpacing.md),
                    _GroupManagerActions(
                      organisation: organisation,
                      group: group,
                    ),
                    const SizedBox(height: LocalLinkSpacing.md),
                    _JoinRequestsPanel(
                      organisation: organisation,
                      group: group,
                      service: _service,
                    ),
                    const SizedBox(height: LocalLinkSpacing.md),
                    _MembersPanel(
                      organisation: organisation,
                      group: group,
                      service: _service,
                      canManage: true,
                    ),
                  ],
                  const SizedBox(height: LocalLinkSpacing.lg),
                  const LocalLinkSectionHeader(title: 'Upcoming'),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  _GroupActivitiesList(
                    organisation: organisation,
                    group: group,
                    service: _service,
                    canManage: canManage,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return 'Group';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onTap});

  final OrganisationGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      _titleCase(group.displayType),
      membershipModeLabel(group.membershipMode),
      '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'}',
      if (group.leaderUserIds.isNotEmpty)
        '${group.leaderUserIds.length} ${group.leaderUserIds.length == 1 ? 'leader' : 'leaders'}',
      if (group.ageLabel.isNotEmpty) group.ageLabel,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        onTap: onTap,
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: LocalLinkImage(
                imageUrl: group.imageUrl,
                fallbackIcon: Icons.groups_2_outlined,
                accentColor: AppColors.activityBlue,
                semanticLabel: '${group.name} image',
              ),
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: LocalLinkTextStyles.cardTitle),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    metadata.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.metadata,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return 'Group';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.organisation, required this.group});

  final Organisation organisation;
  final OrganisationGroup group;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(LocalLinkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalLinkImage(
            imageUrl: group.imageUrl,
            aspectRatio: 16 / 8,
            fallbackIcon: Icons.groups_2_outlined,
            accentColor: AppColors.activityBlue,
            semanticLabel: '${group.name} image',
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          Text(group.name, style: LocalLinkTextStyles.screenTitle),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(organisation.name, style: LocalLinkTextStyles.metadata),
          const SizedBox(height: LocalLinkSpacing.sm),
          Wrap(
            spacing: LocalLinkSpacing.xs,
            runSpacing: LocalLinkSpacing.xs,
            children: [
              _Pill(label: _titleCase(group.displayType)),
              if (group.category.isNotEmpty) _Pill(label: group.category),
              if (group.subcategory.isNotEmpty) _Pill(label: group.subcategory),
              if (group.ageLabel.isNotEmpty) _Pill(label: group.ageLabel),
            ],
          ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: LocalLinkSpacing.md),
            Text(group.description, style: LocalLinkTextStyles.body),
          ],
        ],
      ),
    );
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return 'Group';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _MembershipCard extends StatefulWidget {
  const _MembershipCard({
    required this.organisation,
    required this.group,
    required this.service,
    required this.canManage,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final OrganisationService service;
  final bool canManage;

  @override
  State<_MembershipCard> createState() => _MembershipCardState();
}

class _MembershipCardState extends State<_MembershipCard> {
  bool _busy = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final status = await widget.service.joinOrRequestGroup(
        organisation: widget.organisation,
        group: widget.group,
      );
      if (!mounted) return;
      final message = switch (status) {
        'pending' => 'Request sent.',
        'invite_only' => 'This group is invite only.',
        _ => 'You joined this group.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membership could not be updated.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      await widget.service.leaveGroup(
        organisationId: widget.organisation.id,
        groupId: widget.group.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You left this group.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membership could not be updated.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return _InfoCard(
        label: 'Join this group',
        text: 'Sign in to join or request access.',
      );
    }

    if (widget.canManage) {
      final label = widget.group.isLedBy(user.uid)
          ? 'Group leader'
          : 'Organisation manager';
      return _InfoCard(
        label: label,
        text:
            'You can manage this group without joining it as a regular member.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.service.watchGroupMembership(
        organisationId: widget.organisation.id,
        groupId: widget.group.id,
        userId: user.uid,
      ),
      builder: (context, memberSnapshot) {
        final isMember = memberSnapshot.data?.data()?['status'] == 'active';
        if (isMember) {
          return _InfoCard(
            label: 'Member',
            text: 'You receive updates for this group.',
            action: LocalLinkButton(
              label: _busy ? 'Leaving...' : 'Leave group',
              icon: Icons.logout_rounded,
              onPressed: _busy ? null : _leave,
              variant: LocalLinkButtonVariant.secondary,
              isLoading: _busy,
            ),
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.service.watchJoinRequest(
            organisationId: widget.organisation.id,
            groupId: widget.group.id,
            userId: user.uid,
          ),
          builder: (context, requestSnapshot) {
            final requestStatus = requestSnapshot.data?.data()?['status'];
            if (requestStatus == 'pending') {
              return const _InfoCard(
                label: 'Request pending',
                text: 'A group leader or organisation admin will review this.',
              );
            }

            final label = widget.group.requiresApproval
                ? 'Request to join'
                : widget.group.isInviteOnly
                ? 'Invite only'
                : 'Join group';
            return _InfoCard(
              label: label,
              text: widget.group.requiresApproval
                  ? 'This group reviews new members before they join.'
                  : widget.group.isInviteOnly
                  ? 'Ask the organiser for an invitation.'
                  : 'Join once to receive relevant group information.',
              action: widget.group.isInviteOnly
                  ? null
                  : LocalLinkButton(
                      label: _busy ? 'Working...' : label,
                      icon: Icons.person_add_alt_1_outlined,
                      onPressed: _busy ? null : _join,
                      isLoading: _busy,
                      expand: true,
                    ),
            );
          },
        );
      },
    );
  }
}

class _GroupManagerActions extends StatelessWidget {
  const _GroupManagerActions({required this.organisation, required this.group});

  final Organisation organisation;
  final OrganisationGroup group;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quick actions', style: LocalLinkTextStyles.label),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkButton(
            label: 'Add activity',
            icon: Icons.event_available_outlined,
            variant: LocalLinkButtonVariant.secondary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateOpportunityScreen(
                  organisation: organisation,
                  group: group,
                  initialActivityKind: 'activity',
                ),
              ),
            ),
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _GroupLeadersSection extends StatelessWidget {
  const _GroupLeadersSection({
    required this.organisation,
    required this.group,
    required this.service,
  });

  final Organisation organisation;
  final OrganisationGroup? group;
  final OrganisationService service;

  @override
  Widget build(BuildContext context) {
    final group = this.group;
    return LocalLinkFormSection(
      title: 'Group leaders',
      children: [
        if (group == null)
          Text(
            'Save this group before assigning leaders.',
            style: LocalLinkTextStyles.secondary,
          )
        else
          StreamBuilder<List<OrganisationMembership>>(
            stream: service.watchOrganisationPeople(organisation.id),
            builder: (context, snapshot) {
              final people = snapshot.data ?? const <OrganisationMembership>[];
              final leaderNames = groupLeaderDisplayNames(
                group: group,
                people: people,
              );
              final assignedCount = group.leaderUserIds.length;
              final leaderText = leaderNames.isNotEmpty
                  ? leaderNames.join(', ')
                  : assignedCount > 0
                  ? '$assignedCount ${assignedCount == 1 ? 'leader assigned' : 'leaders assigned'}'
                  : 'No leaders assigned yet';

              return Text(leaderText, style: LocalLinkTextStyles.secondary);
            },
          ),
        const SizedBox(height: LocalLinkSpacing.md),
        LocalLinkButton(
          label: 'Manage leaders',
          icon: Icons.manage_accounts_outlined,
          onPressed: group == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        OrganisationPeopleScreen(organisation: organisation),
                  ),
                ),
          variant: LocalLinkButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class _GroupImageEditor extends StatelessWidget {
  const _GroupImageEditor({
    required this.imageUrl,
    required this.selectedImage,
    required this.selectedImageBytes,
    required this.removeImage,
    required this.onPick,
    required this.onRemove,
  });

  final String imageUrl;
  final XFile? selectedImage;
  final Uint8List? selectedImageBytes;
  final bool removeImage;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasExisting = imageUrl.trim().isNotEmpty && !removeImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LocalLinkRadius.md),
            child: selectedImage != null
                ? selectedImageBytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                : LocalLinkImage(
                    imageUrl: hasExisting ? imageUrl : '',
                    aspectRatio: 16 / 8,
                    fallbackIcon: Icons.groups_2_outlined,
                    accentColor: AppColors.activityBlue,
                    semanticLabel: 'Group image',
                  ),
          ),
        ),
        const SizedBox(height: LocalLinkSpacing.xs),
        Wrap(
          spacing: LocalLinkSpacing.xs,
          runSpacing: LocalLinkSpacing.xs,
          children: [
            LocalLinkButton(
              label: hasExisting || selectedImage != null
                  ? 'Change image'
                  : 'Add image',
              icon: Icons.add_photo_alternate_outlined,
              onPressed: onPick,
              variant: LocalLinkButtonVariant.secondary,
            ),
            if (onRemove != null)
              LocalLinkButton(
                label: 'Remove image',
                icon: Icons.delete_outline,
                onPressed: onRemove,
                variant: LocalLinkButtonVariant.secondary,
              ),
          ],
        ),
      ],
    );
  }
}

class _JoinRequestsPanel extends StatelessWidget {
  const _JoinRequestsPanel({
    required this.organisation,
    required this.group,
    required this.service,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final OrganisationService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchGroupJoinRequests(
        organisationId: organisation.id,
        groupId: group.id,
      ),
      builder: (context, snapshot) {
        final requests = (snapshot.data?.docs ?? const []).toList()
          ..sort((a, b) {
            final aDate = a.data()['createdAt'];
            final bDate = b.data()['createdAt'];
            if (aDate is Timestamp && bDate is Timestamp) {
              return bDate.compareTo(aDate);
            }
            return 0;
          });
        if (requests.isEmpty) return const SizedBox.shrink();
        return LocalLinkSurfaceCard(
          elevated: false,
          padding: const EdgeInsets.all(LocalLinkSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join requests', style: LocalLinkTextStyles.label),
              const SizedBox(height: LocalLinkSpacing.sm),
              for (final request in requests)
                _JoinRequestTile(
                  organisation: organisation,
                  group: group,
                  request: request,
                  service: service,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({
    required this.organisation,
    required this.group,
    required this.request,
    required this.service,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final QueryDocumentSnapshot<Map<String, dynamic>> request;
  final OrganisationService service;

  @override
  Widget build(BuildContext context) {
    final data = request.data();
    final userName = data['userName']?.toString() ?? 'LocalLink member';
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(userName, style: LocalLinkTextStyles.bodyStrong),
          ),
          TextButton(
            onPressed: () => service.declineJoinRequest(
              organisation: organisation,
              group: group,
              userId: request.id,
            ),
            child: const Text('Decline'),
          ),
          const SizedBox(width: LocalLinkSpacing.xs),
          FilledButton(
            onPressed: () => service.approveJoinRequest(
              organisation: organisation,
              group: group,
              userId: request.id,
              userName: userName,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }
}

class _MembersPanel extends StatelessWidget {
  const _MembersPanel({
    required this.organisation,
    required this.group,
    required this.service,
    required this.canManage,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final OrganisationService service;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchGroupMembers(
        organisationId: organisation.id,
        groupId: group.id,
      ),
      builder: (context, snapshot) {
        final members = (snapshot.data?.docs ?? const []).toList()
          ..sort((a, b) {
            final aName = a.data()['userName']?.toString() ?? '';
            final bName = b.data()['userName']?.toString() ?? '';
            return aName.compareTo(bName);
          });
        return LocalLinkSurfaceCard(
          elevated: false,
          padding: const EdgeInsets.all(LocalLinkSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Members', style: LocalLinkTextStyles.label),
              const SizedBox(height: LocalLinkSpacing.sm),
              if (members.isEmpty)
                Text('No members yet.', style: LocalLinkTextStyles.metadata)
              else
                for (final member in members)
                  _MemberTile(
                    organisation: organisation,
                    group: group,
                    member: member,
                    service: service,
                    canManage: canManage,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.organisation,
    required this.group,
    required this.member,
    required this.service,
    required this.canManage,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final QueryDocumentSnapshot<Map<String, dynamic>> member;
  final OrganisationService service;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final data = member.data();
    final userName = data['userName']?.toString() ?? 'LocalLink member';
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(userName, style: LocalLinkTextStyles.body)),
          if (canManage)
            TextButton(
              onPressed: () => service.removeMember(
                organisationId: organisation.id,
                groupId: group.id,
                userId: member.id,
              ),
              child: const Text('Remove'),
            ),
        ],
      ),
    );
  }
}

class _GroupActivitiesList extends StatelessWidget {
  const _GroupActivitiesList({
    required this.organisation,
    required this.group,
    required this.service,
    required this.canManage,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final OrganisationService service;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (!canManage && (user == null || user.isAnonymous)) {
      return const LocalLinkEmptyState(
        icon: Icons.event_busy_outlined,
        title: 'No public sessions shown',
        message: 'Join the group to see member sessions and events.',
      );
    }
    if (!canManage) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: service.watchGroupMembership(
          organisationId: organisation.id,
          groupId: group.id,
          userId: user!.uid,
        ),
        builder: (context, snapshot) {
          final isMember = snapshot.data?.data()?['status'] == 'active';
          if (!isMember) {
            return const LocalLinkEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No public sessions shown',
              message: 'Join the group to see member sessions and events.',
            );
          }
          return _GroupActivityStream(
            organisation: organisation,
            group: group,
            service: service,
          );
        },
      );
    }
    return _GroupActivityStream(
      organisation: organisation,
      group: group,
      service: service,
      canManage: true,
    );
  }
}

class _GroupActivityStream extends StatelessWidget {
  const _GroupActivityStream({
    required this.organisation,
    required this.group,
    required this.service,
    this.canManage = false,
  });

  final Organisation organisation;
  final OrganisationGroup group;
  final OrganisationService service;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchGroupActivities(
        organisationId: organisation.id,
        groupId: group.id,
        canManage: canManage,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const LocalLinkErrorState(
            title: 'Activities could not be loaded',
            message: 'Please try again in a moment.',
          );
        }
        if (!snapshot.hasData) {
          return const LocalLinkLoadingState(label: 'Loading activities');
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aDate = a.data()['eventDate'];
            final bDate = b.data()['eventDate'];
            if (aDate is Timestamp && bDate is Timestamp) {
              return aDate.compareTo(bDate);
            }
            return 0;
          });
        if (docs.isEmpty) {
          return const LocalLinkEmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No sessions yet',
            message:
                'Future sessions and events for this group will appear here.',
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            return _GroupActivityTile(
              title: data['title']?.toString() ?? 'Activity',
              subtitle:
                  [
                        data['activityKind']?.toString(),
                        data['scheduleText']?.toString(),
                        data['location']?.toString(),
                      ]
                      .where(
                        (value) => value != null && value.trim().isNotEmpty,
                      )
                      .join(' · '),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OpportunityDetailScreen(
                    opportunityId: doc.id,
                    opportunity: data,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _GroupActivityTile extends StatelessWidget {
  const _GroupActivityTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        onTap: onTap,
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            const LocalLinkIconBadge(
              icon: Icons.event_available_outlined,
              color: AppColors.activityBlue,
              size: 42,
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LocalLinkTextStyles.cardTitle),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LocalLinkTextStyles.metadata,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.text, this.action});

  final String label;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      color: AppColors.activitySoft,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LocalLinkTextStyles.label.copyWith(
              color: AppColors.activityBlue,
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(text, style: LocalLinkTextStyles.secondary),
          if (action != null) ...[
            const SizedBox(height: LocalLinkSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.activityBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
      child: Text(
        label,
        style: LocalLinkTextStyles.status.copyWith(
          color: AppColors.activityBlue,
        ),
      ),
    );
  }
}
