import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/organisation.dart';
import '../models/organisation_role.dart';
import '../services/organisation_service.dart';
import '../services/organisation_permissions.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';
import 'create_opportunity_screen.dart';
import 'opportunity_detail_screen.dart';
import 'organisation_announcements_screen.dart';
import 'organisation_detail_screen.dart';
import 'organisation_group_screens.dart';
import 'organisation_people_screen.dart';

class OrganisationManagementScreen extends StatelessWidget {
  OrganisationManagementScreen({super.key, required this.organisation})
    : _service = OrganisationService();

  final Organisation organisation;
  final OrganisationService _service;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isDirectManager = organisation.isManagedBy(uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Your organisation'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: isDirectManager || uid == null
          ? _buildBody(
              context,
              canManageOrganisation: isDirectManager,
              canManageGroups: isDirectManager,
            )
          : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('organisations')
                  .doc(organisation.id)
                  .collection('members')
                  .doc(uid)
                  .get(),
              builder: (context, snapshot) {
                final role = normaliseOrganisationRole(
                  snapshot.data?.data()?['role']?.toString() ?? '',
                );
                final canManageOrganisation =
                    OrganisationPermissions.isOrganisationManagerRole(role);
                final canManageGroups =
                    canManageOrganisation ||
                    role == organisationRoleGroupLeader;

                return _buildBody(
                  context,
                  canManageOrganisation: canManageOrganisation,
                  canManageGroups: canManageGroups,
                );
              },
            ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool canManageOrganisation,
    required bool canManageGroups,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _OrganisationManageHeader(organisation: organisation),
        const SizedBox(height: LocalLinkSpacing.lg),
        const LocalLinkSectionHeader(title: 'Manage'),
        const SizedBox(height: LocalLinkSpacing.sm),
        _ManagementAction(
          icon: Icons.visibility_outlined,
          title: 'View organisation',
          subtitle: 'See what people can find on LocalLink.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OrganisationDetailScreen(organisationId: organisation.id),
            ),
          ),
        ),
        if (canManageGroups)
          _ManagementAction(
            icon: Icons.account_tree_outlined,
            title: groupCollectionLabel(organisation),
            subtitle: canManageOrganisation
                ? 'Create and manage teams, sections or classes.'
                : 'Manage the groups assigned to you.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    OrganisationGroupsScreen(organisation: organisation),
              ),
            ),
          ),
        if (canManageOrganisation)
          _ManagementAction(
            icon: Icons.people_outline,
            title: 'People',
            subtitle: 'Invite helpers, assign roles and manage members.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    OrganisationPeopleScreen(organisation: organisation),
              ),
            ),
          ),
        if (canManageOrganisation)
          _ManagementAction(
            icon: Icons.add_circle_outline_rounded,
            title: 'Add activity',
            subtitle: 'Create another class, session or event.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CreateOpportunityScreen(organisation: organisation),
              ),
            ),
          ),
        if (canManageOrganisation)
          _ManagementAction(
            icon: Icons.campaign_outlined,
            title: 'Announcements',
            subtitle: 'Send a clear update to everyone or one group.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    OrganisationAnnouncementsScreen(organisation: organisation),
              ),
            ),
          ),
        if (canManageOrganisation)
          _ManagementAction(
            icon: Icons.edit_note_rounded,
            title: 'Settings',
            subtitle: 'Update public details and contact information.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    OrganisationEditScreen(organisation: organisation),
              ),
            ),
          ),
        const SizedBox(height: LocalLinkSpacing.lg),
        const LocalLinkSectionHeader(
          title: 'Existing activities',
          subtitle: 'Open an activity to manage its details.',
        ),
        const SizedBox(height: LocalLinkSpacing.sm),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _service.watchOrganisationActivities(organisation.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const LocalLinkErrorState(
                title: 'Activities could not be loaded',
                message: 'Please try again in a moment.',
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: LocalLinkSpacing.xxl),
                child: LocalLinkLoadingState(label: 'Loading activities'),
              );
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
                icon: Icons.event_available_outlined,
                title: 'No activities yet',
                message:
                    'Add your first class, session or event for this organisation.',
              );
            }

            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                return _ActivityManageTile(
                  title: data['title']?.toString() ?? 'Activity',
                  subtitle:
                      [
                            data['scheduleText']?.toString().trim(),
                            data['location']?.toString().trim(),
                          ]
                          .where((value) => value != null && value.isNotEmpty)
                          .cast<String>()
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
        ),
      ],
    );
  }
}

class OrganisationEditScreen extends StatefulWidget {
  const OrganisationEditScreen({super.key, required this.organisation});

  final Organisation organisation;

  @override
  State<OrganisationEditScreen> createState() => _OrganisationEditScreenState();
}

class _OrganisationEditScreenState extends State<OrganisationEditScreen> {
  final _service = OrganisationService();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _subcategoriesController;
  late final TextEditingController _locationController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _websiteController;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _removeImage = false;
  bool _saving = false;
  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    final organisation = widget.organisation;
    _nameController = TextEditingController(text: organisation.name);
    _descriptionController = TextEditingController(
      text: organisation.description,
    );
    _categoryController = TextEditingController(text: organisation.category);
    _subcategoriesController = TextEditingController(
      text: organisation.subcategories.join(', '),
    );
    _locationController = TextEditingController(text: organisation.location);
    _phoneController = TextEditingController(text: organisation.phone);
    _emailController = TextEditingController(text: organisation.email);
    _websiteController = TextEditingController(text: organisation.website);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _subcategoriesController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an organisation name.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_selectedImage != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null || user.isAnonymous) {
          throw StateError('Sign in required.');
        }
        final ref = FirebaseStorage.instance.ref().child(
          'organisationPhotos/${widget.organisation.id}/${DateTime.now().millisecondsSinceEpoch}.jpg',
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
      final subcategories = _subcategoriesController.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      await FirebaseFirestore.instance
          .collection('organisations')
          .doc(widget.organisation.id)
          .update({
            'name': name,
            'description': _descriptionController.text.trim(),
            'category': _categoryController.text.trim(),
            'subcategories': subcategories,
            'location': _locationController.text.trim(),
            'publicLocation': _locationController.text.trim().isNotEmpty
                ? _locationController.text.trim()
                : widget.organisation.publicLocation,
            'phone': _phoneController.text.trim(),
            'email': _emailController.text.trim(),
            'website': _websiteController.text.trim(),
            'capabilities': OrganisationCapabilities.defaultsFor(
              category: _categoryController.text.trim(),
              subcategories: subcategories,
              name: name,
            ).toMap(),
            ...?imageUrl == null ? null : {'imageUrl': imageUrl},
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Organisation updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organisation could not be updated.')),
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
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selectedImage = image;
      _selectedImageBytes = bytes;
      _removeImage = false;
    });
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive organisation?'),
        content: const Text(
          'This hides the organisation and its public activities from LocalLink. You can restore it later from My LocalLink.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _archiving = true);
    try {
      await _service.archiveOrganisation(
        organisationId: widget.organisation.id,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Organisation archived.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organisation could not be archived.')),
      );
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edit organisation'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          LocalLinkFormSection(
            title: 'Organisation identity',
            helperText:
                'Help people understand who you are and what you offer locally.',
            children: [
              _OrganisationImageEditor(
                imageUrl: widget.organisation.imageUrl,
                selectedImageBytes: _selectedImageBytes,
                removeImage: _removeImage,
                onPick: _pickImage,
                onRemove:
                    (widget.organisation.imageUrl.isNotEmpty ||
                        _selectedImageBytes != null)
                    ? () => setState(() {
                        _selectedImage = null;
                        _selectedImageBytes = null;
                        _removeImage = true;
                      })
                    : null,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _nameController,
                label: 'Organisation name',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _descriptionController,
                maxLines: 4,
                label: 'Description',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _categoryController,
                label: 'Category',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _subcategoriesController,
                label: 'Subcategories',
                hintText: 'Rugby, junior sport, training',
              ),
            ],
          ),
          LocalLinkFormSection(
            title: 'Public contact details',
            helperText:
                'Only add details you are happy for people nearby to see.',
            children: [
              LocalLinkFormField(
                controller: _locationController,
                label: 'Location',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _phoneController,
                label: 'Contact phone',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _emailController,
                label: 'Contact email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _websiteController,
                label: 'Website',
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          LocalLinkButton(
            label: _saving ? 'Saving...' : 'Save organisation',
            onPressed: _saving ? null : _save,
            isLoading: _saving,
            expand: true,
          ),
          if (FirebaseAuth.instance.currentUser?.uid ==
              widget.organisation.ownerId) ...[
            const SizedBox(height: LocalLinkSpacing.lg),
            LocalLinkFormSection(
              title: 'Archive',
              helperText:
                  'Hide this organisation from LocalLink without deleting its history.',
              children: [
                LocalLinkButton(
                  label: _archiving ? 'Archiving...' : 'Archive organisation',
                  icon: Icons.inventory_2_outlined,
                  onPressed: _archiving ? null : _archive,
                  isLoading: _archiving,
                  variant: LocalLinkButtonVariant.secondary,
                  expand: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OrganisationImageEditor extends StatelessWidget {
  const _OrganisationImageEditor({
    required this.imageUrl,
    required this.selectedImageBytes,
    required this.removeImage,
    required this.onPick,
    required this.onRemove,
  });

  final String imageUrl;
  final Uint8List? selectedImageBytes;
  final bool removeImage;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty && !removeImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LocalLinkRadius.md),
            child: selectedImageBytes != null
                ? Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                : LocalLinkImage(
                    imageUrl: hasImage ? imageUrl : '',
                    aspectRatio: 16 / 8,
                    fallbackIcon: Icons.groups_2_outlined,
                    accentColor: AppColors.activityBlue,
                    semanticLabel: 'Organisation image',
                  ),
          ),
        ),
        const SizedBox(height: LocalLinkSpacing.xs),
        Wrap(
          spacing: LocalLinkSpacing.xs,
          runSpacing: LocalLinkSpacing.xs,
          children: [
            LocalLinkButton(
              label: hasImage || selectedImageBytes != null
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

class _OrganisationManageHeader extends StatelessWidget {
  const _OrganisationManageHeader({required this.organisation});

  final Organisation organisation;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: LocalLinkImage(
              imageUrl: organisation.imageUrl,
              fallbackIcon: Icons.groups_2_outlined,
              accentColor: AppColors.activityBlue,
              semanticLabel: 'Organisation image',
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  organisation.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 18),
                ),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(
                  [
                    if (organisation.category.isNotEmpty) organisation.category,
                    if (organisation.publicLocation.isNotEmpty)
                      organisation.publicLocation,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.metadata,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagementAction extends StatelessWidget {
  const _ManagementAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
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
            LocalLinkIconBadge(
              icon: icon,
              color: AppColors.activityBlue,
              size: 42,
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LocalLinkTextStyles.cardTitle),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    subtitle,
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
}

class _ActivityManageTile extends StatelessWidget {
  const _ActivityManageTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ManagementAction(
      icon: Icons.event_available_outlined,
      title: title,
      subtitle: subtitle.isEmpty ? 'Activity details' : subtitle,
      onTap: onTap,
    );
  }
}
