import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../models/organisation_role.dart';
import '../services/organisation_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_chip.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';

class OrganisationPeopleScreen extends StatefulWidget {
  const OrganisationPeopleScreen({
    super.key,
    required this.organisation,
    this.service,
  });

  final Organisation organisation;
  final OrganisationService? service;

  @override
  State<OrganisationPeopleScreen> createState() =>
      _OrganisationPeopleScreenState();
}

class _OrganisationPeopleScreenState extends State<OrganisationPeopleScreen> {
  final _emailController = TextEditingController();
  final _displayRoleController = TextEditingController();
  OrganisationService? _service;
  String _role = organisationRoleMember;
  final Set<String> _groupIds = {};
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    _displayRoleController.dispose();
    super.dispose();
  }

  OrganisationService get _organisationService =>
      widget.service ?? (_service ??= OrganisationService());

  Future<void> _sendInvite() async {
    final email = _emailController.text.trim();
    if (!_isEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    if (_role == organisationRoleGroupLeader && _groupIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one group.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _organisationService.invitePerson(
        organisationId: widget.organisation.id,
        email: email,
        role: _role,
        groupIds: _groupIds.toList(),
        displayRole: _displayRoleController.text,
      );
      if (!mounted) return;
      _emailController.clear();
      _displayRoleController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation sent.')));
    } catch (error, stackTrace) {
      debugPrint('Organisation invitation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation could not be sent.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('People & roles'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: StreamBuilder<List<OrganisationGroup>>(
        stream: _organisationService.watchGroups(widget.organisation.id),
        builder: (context, groupSnapshot) {
          final groups = groupSnapshot.data ?? const <OrganisationGroup>[];
          final groupNames = {for (final group in groups) group.id: group.name};

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              LocalLinkSectionHeader(
                title: widget.organisation.name,
                subtitle: 'Invite helpers, assign roles and manage members.',
              ),
              const SizedBox(height: LocalLinkSpacing.md),
              _InviteCard(
                emailController: _emailController,
                displayRoleController: _displayRoleController,
                role: _role,
                groupIds: _groupIds,
                groups: groups,
                sending: _sending,
                onRoleChanged: (role) => setState(() {
                  _role = role;
                  if (role != organisationRoleGroupLeader) _groupIds.clear();
                }),
                onGroupToggled: (groupId) => setState(() {
                  if (!_groupIds.add(groupId)) {
                    _groupIds.remove(groupId);
                  }
                }),
                onSend: _sendInvite,
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              const LocalLinkSectionHeader(title: 'People'),
              const SizedBox(height: LocalLinkSpacing.sm),
              StreamBuilder<List<OrganisationMembership>>(
                stream: _organisationService.watchOrganisationPeople(
                  widget.organisation.id,
                ),
                builder: (context, peopleSnapshot) {
                  if (peopleSnapshot.hasError) {
                    return const LocalLinkErrorState(
                      title: 'People could not be loaded',
                      message: 'Please try again in a moment.',
                    );
                  }
                  if (!peopleSnapshot.hasData) {
                    return const LocalLinkLoadingState(label: 'Loading people');
                  }

                  final people = peopleSnapshot.data!;
                  final owner = _ownerAsMember(widget.organisation, people);
                  final visiblePeople = [
                    ?owner,
                    ...people.where((person) => person.userId != owner?.userId),
                  ];

                  if (visiblePeople.isEmpty) {
                    return const LocalLinkEmptyState(
                      icon: Icons.people_outline,
                      title: 'No people yet',
                      message: 'Invite someone when you are ready.',
                    );
                  }

                  return Column(
                    children: [
                      for (final person in visiblePeople)
                        _PersonTile(
                          organisation: widget.organisation,
                          person: person,
                          groups: groups,
                          groupNames: groupNames,
                          service: _organisationService,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              const LocalLinkSectionHeader(title: 'Invitations'),
              const SizedBox(height: LocalLinkSpacing.sm),
              _InvitationsList(
                organisation: widget.organisation,
                service: _organisationService,
                groupNames: groupNames,
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _isEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  static OrganisationMembership? _ownerAsMember(
    Organisation organisation,
    List<OrganisationMembership> people,
  ) {
    final ownerId = organisation.ownerId;
    if (ownerId.isEmpty) return null;
    final existing = people.where((person) => person.userId == ownerId);
    if (existing.isNotEmpty) {
      final owner = existing.first;
      return OrganisationMembership(
        userId: owner.userId,
        userName: owner.userName.isEmpty ? 'Owner' : owner.userName,
        status: owner.status,
        role: organisationRoleOwner,
        groupIds: owner.groupIds,
        createdAt: owner.createdAt,
        updatedAt: owner.updatedAt,
      );
    }
    return OrganisationMembership(
      userId: ownerId,
      userName: 'Owner',
      status: 'active',
      role: organisationRoleOwner,
      groupIds: const [],
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.emailController,
    required this.displayRoleController,
    required this.role,
    required this.groupIds,
    required this.groups,
    required this.sending,
    required this.onRoleChanged,
    required this.onGroupToggled,
    required this.onSend,
  });

  final TextEditingController emailController;
  final TextEditingController displayRoleController;
  final String role;
  final Set<String> groupIds;
  final List<OrganisationGroup> groups;
  final bool sending;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onGroupToggled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return LocalLinkFormSection(
      title: 'Invite someone',
      helperText: 'Send an invitation to someone who helps run or join this.',
      children: [
        LocalLinkFormField(
          controller: emailController,
          label: 'Email address',
          hintText: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: LocalLinkSpacing.sm),
        Text('Role', style: LocalLinkTextStyles.label),
        const SizedBox(height: LocalLinkSpacing.xs),
        Wrap(
          spacing: LocalLinkSpacing.xs,
          runSpacing: LocalLinkSpacing.xs,
          children: [
            for (final option in organisationInviteRoles)
              LocalLinkChip(
                label: organisationRoleLabel(option),
                selected: role == option,
                accentColor: AppColors.activityBlue,
                onSelected: (_) => onRoleChanged(option),
              ),
          ],
        ),
        if (role == organisationRoleGroupLeader) ...[
          const SizedBox(height: LocalLinkSpacing.md),
          Text('Groups they can manage', style: LocalLinkTextStyles.label),
          const SizedBox(height: LocalLinkSpacing.xs),
          Wrap(
            spacing: LocalLinkSpacing.xs,
            runSpacing: LocalLinkSpacing.xs,
            children: [
              for (final group in groups)
                LocalLinkChip(
                  label: group.name,
                  selected: groupIds.contains(group.id),
                  accentColor: AppColors.activityBlue,
                  onSelected: (_) => onGroupToggled(group.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: LocalLinkSpacing.sm),
        LocalLinkFormField(
          controller: displayRoleController,
          label: 'Display label',
          hintText: 'Coach, leader, secretary',
        ),
        const SizedBox(height: LocalLinkSpacing.md),
        LocalLinkButton(
          label: sending ? 'Sending...' : 'Send invitation',
          icon: Icons.mail_outline,
          onPressed: sending ? null : onSend,
          isLoading: sending,
          expand: true,
        ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.organisation,
    required this.person,
    required this.groups,
    required this.groupNames,
    required this.service,
  });

  final Organisation organisation;
  final OrganisationMembership person;
  final List<OrganisationGroup> groups;
  final Map<String, String> groupNames;
  final OrganisationService service;

  @override
  Widget build(BuildContext context) {
    final groups = person.groupIds
        .map((id) => groupNames[id] ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
    final role = organisationRoleLabel(person.role);
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        onTap: person.role == organisationRoleOwner
            ? null
            : () => _openManageSheet(context),
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            const LocalLinkIconBadge(
              icon: Icons.person_outline,
              color: AppColors.activityBlue,
              size: 42,
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.userName, style: LocalLinkTextStyles.cardTitle),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    groups.isEmpty ? role : '$role · $groups',
                    style: LocalLinkTextStyles.metadata,
                  ),
                ],
              ),
            ),
            Icon(
              person.role == organisationRoleOwner
                  ? Icons.lock_outline
                  : Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _openManageSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ManagePersonSheet(
        organisation: organisation,
        person: person,
        groups: groups,
        service: service,
      ),
    );
  }
}

class _ManagePersonSheet extends StatefulWidget {
  const _ManagePersonSheet({
    required this.organisation,
    required this.person,
    required this.groups,
    required this.service,
  });

  final Organisation organisation;
  final OrganisationMembership person;
  final List<OrganisationGroup> groups;
  final OrganisationService service;

  @override
  State<_ManagePersonSheet> createState() => _ManagePersonSheetState();
}

class _ManagePersonSheetState extends State<_ManagePersonSheet> {
  late String _role;
  late final Set<String> _groupIds;
  bool _saving = false;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _role = normaliseOrganisationRole(widget.person.role);
    _groupIds = widget.person.groupIds.toSet();
  }

  Future<void> _save() async {
    if (_role == organisationRoleGroupLeader && _groupIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one group.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.service.updatePersonRole(
        organisationId: widget.organisation.id,
        userId: widget.person.userId,
        role: _role,
        groupIds: _role == organisationRoleGroupLeader
            ? _groupIds.toList()
            : const [],
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Person updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Person could not be updated.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove person?'),
        content: Text(
          '${widget.person.userName} will lose access to this organisation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _removing = true);
    try {
      await widget.service.removePerson(
        organisationId: widget.organisation.id,
        userId: widget.person.userId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Person removed.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Person could not be removed.')),
      );
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: LocalLinkSurfaceCard(
          padding: const EdgeInsets.all(LocalLinkSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.person.userName,
                style: LocalLinkTextStyles.cardTitle,
              ),
              const SizedBox(height: LocalLinkSpacing.xs),
              Text(
                'Manage role and group access.',
                style: LocalLinkTextStyles.metadata,
              ),
              const SizedBox(height: LocalLinkSpacing.md),
              Text('Role', style: LocalLinkTextStyles.label),
              const SizedBox(height: LocalLinkSpacing.xs),
              Wrap(
                spacing: LocalLinkSpacing.xs,
                runSpacing: LocalLinkSpacing.xs,
                children: [
                  for (final role in organisationInviteRoles)
                    LocalLinkChip(
                      label: organisationRoleLabel(role),
                      selected: _role == role,
                      accentColor: AppColors.activityBlue,
                      onSelected: (_) => setState(() {
                        _role = role;
                        if (role != organisationRoleGroupLeader) {
                          _groupIds.clear();
                        }
                      }),
                    ),
                ],
              ),
              if (_role == organisationRoleGroupLeader) ...[
                const SizedBox(height: LocalLinkSpacing.md),
                Text(
                  'Groups they can manage',
                  style: LocalLinkTextStyles.label,
                ),
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xs,
                  children: [
                    for (final group in widget.groups)
                      LocalLinkChip(
                        label: group.name,
                        selected: _groupIds.contains(group.id),
                        accentColor: AppColors.activityBlue,
                        onSelected: (_) => setState(() {
                          if (!_groupIds.add(group.id)) {
                            _groupIds.remove(group.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: LocalLinkSpacing.lg),
              LocalLinkButton(
                label: _saving ? 'Saving...' : 'Save changes',
                onPressed: _saving || _removing ? null : _save,
                isLoading: _saving,
                expand: true,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkButton(
                label: _removing ? 'Removing...' : 'Remove from organisation',
                icon: Icons.person_remove_outlined,
                onPressed: _saving || _removing ? null : _remove,
                isLoading: _removing,
                variant: LocalLinkButtonVariant.secondary,
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitationsList extends StatelessWidget {
  const _InvitationsList({
    required this.organisation,
    required this.service,
    required this.groupNames,
  });

  final Organisation organisation;
  final OrganisationService service;
  final Map<String, String> groupNames;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchOrganisationInvitations(organisation.id),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? const []).toList()
          ..sort((a, b) {
            final aDate = a.data()['createdAt'];
            final bDate = b.data()['createdAt'];
            if (aDate is Timestamp && bDate is Timestamp) {
              return bDate.compareTo(aDate);
            }
            return 0;
          });
        if (docs.isEmpty) {
          return const Text('No pending invitations.');
        }
        return Column(
          children: [
            for (final doc in docs)
              _InvitationTile(data: doc.data(), groupNames: groupNames),
          ],
        );
      },
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({required this.data, required this.groupNames});

  final Map<String, dynamic> data;
  final Map<String, String> groupNames;

  @override
  Widget build(BuildContext context) {
    final email = data['email']?.toString() ?? '';
    final role = organisationRoleLabel(data['role']?.toString() ?? '');
    final groupId = data['groupId']?.toString() ?? '';
    final groupName = groupNames[groupId] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.mark_email_unread_outlined),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Text(
                groupName.isEmpty
                    ? '$email · $role'
                    : '$email · $role · $groupName',
                style: LocalLinkTextStyles.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
