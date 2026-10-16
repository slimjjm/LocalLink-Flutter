import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../services/organisation_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_chip.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';

class OrganisationAnnouncementsScreen extends StatefulWidget {
  const OrganisationAnnouncementsScreen({
    super.key,
    required this.organisation,
    this.service,
  });

  final Organisation organisation;
  final OrganisationService? service;

  @override
  State<OrganisationAnnouncementsScreen> createState() =>
      _OrganisationAnnouncementsScreenState();
}

class _OrganisationAnnouncementsScreenState
    extends State<OrganisationAnnouncementsScreen> {
  final _messageController = TextEditingController();
  OrganisationService? _service;
  String _targetGroupId = '';
  String _targetGroupName = '';
  bool _sending = false;

  OrganisationService get _organisationService =>
      widget.service ?? (_service ??= OrganisationService());

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an announcement message.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _organisationService.publishOrganisationAnnouncement(
        organisationId: widget.organisation.id,
        message: message,
        groupId: _targetGroupId,
        groupName: _targetGroupName,
      );
      if (!mounted) return;
      _messageController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Announcement sent.')));
    } catch (error, stackTrace) {
      debugPrint('Organisation announcement failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement could not be sent.')),
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
        title: const Text('Announcements'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: StreamBuilder<List<OrganisationGroup>>(
        stream: _organisationService.watchGroups(widget.organisation.id),
        builder: (context, groupSnapshot) {
          final groups = groupSnapshot.data ?? const <OrganisationGroup>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              LocalLinkSectionHeader(
                title: 'New announcement',
                subtitle:
                    'Share a clear update with your organisation or one group.',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormSection(
                title: 'Send to',
                children: [
                  Wrap(
                    spacing: LocalLinkSpacing.xs,
                    runSpacing: LocalLinkSpacing.xs,
                    children: [
                      LocalLinkChip(
                        label: 'Entire organisation',
                        selected: _targetGroupId.isEmpty,
                        accentColor: AppColors.activityBlue,
                        onSelected: (_) => setState(() {
                          _targetGroupId = '';
                          _targetGroupName = '';
                        }),
                      ),
                      for (final group in groups)
                        LocalLinkChip(
                          label: group.name,
                          selected: _targetGroupId == group.id,
                          accentColor: AppColors.activityBlue,
                          onSelected: (_) => setState(() {
                            _targetGroupId = group.id;
                            _targetGroupName = group.name;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: LocalLinkSpacing.md),
                  LocalLinkFormField(
                    controller: _messageController,
                    label: 'Message',
                    maxLines: 4,
                  ),
                  const SizedBox(height: LocalLinkSpacing.md),
                  LocalLinkButton(
                    label: _sending ? 'Sending...' : 'Send announcement',
                    icon: Icons.campaign_outlined,
                    onPressed: _sending ? null : _send,
                    isLoading: _sending,
                    expand: true,
                  ),
                ],
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              const LocalLinkSectionHeader(title: 'Recent announcements'),
              const SizedBox(height: LocalLinkSpacing.sm),
              _AnnouncementList(
                service: _organisationService,
                organisation: widget.organisation,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnnouncementList extends StatelessWidget {
  const _AnnouncementList({required this.service, required this.organisation});

  final OrganisationService service;
  final Organisation organisation;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchOrganisationAnnouncements(organisation.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const LocalLinkErrorState(
            title: 'Announcements could not be loaded',
            message: 'Please try again in a moment.',
          );
        }
        if (!snapshot.hasData) {
          return const LocalLinkLoadingState(label: 'Loading announcements');
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aDate = a.data()['createdAt'];
            final bDate = b.data()['createdAt'];
            if (aDate is Timestamp && bDate is Timestamp) {
              return bDate.compareTo(aDate);
            }
            return 0;
          });
        if (docs.isEmpty) {
          return const LocalLinkEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            message: 'Sent announcements will appear here.',
          );
        }
        return Column(
          children: [
            for (final doc in docs)
              _AnnouncementCard(
                organisation: organisation,
                service: service,
                announcementId: doc.id,
                data: doc.data(),
              ),
          ],
        );
      },
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({
    required this.organisation,
    required this.service,
    required this.announcementId,
    required this.data,
  });

  final Organisation organisation;
  final OrganisationService service;
  final String announcementId;
  final Map<String, dynamic> data;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _markedRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_markedRead) return;
    _markedRead = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.service
          .markAnnouncementRead(
            organisationId: widget.organisation.id,
            announcementId: widget.announcementId,
          )
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.data['targetName']?.toString() ?? widget.organisation.name,
              style: LocalLinkTextStyles.label,
            ),
            const SizedBox(height: LocalLinkSpacing.xxs),
            Text(
              widget.data['message']?.toString() ?? '',
              style: LocalLinkTextStyles.body,
            ),
          ],
        ),
      ),
    );
  }
}
