import 'package:flutter/material.dart';

import '../services/organisation_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_surface_card.dart';
import 'my_locallink_screen.dart';

class OrganisationInvitationScreen extends StatefulWidget {
  const OrganisationInvitationScreen({
    super.key,
    required this.token,
    OrganisationService? organisationService,
  }) : _organisationService = organisationService;

  final String token;
  final OrganisationService? _organisationService;

  @override
  State<OrganisationInvitationScreen> createState() =>
      _OrganisationInvitationScreenState();
}

class _OrganisationInvitationScreenState
    extends State<OrganisationInvitationScreen> {
  late final OrganisationService _organisationService =
      widget._organisationService ?? OrganisationService();

  bool _isAccepting = false;
  bool _accepted = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _isAccepting = true;
      _error = null;
    });

    try {
      await _organisationService.acceptInvitation(token: widget.token);
      if (!mounted) return;
      setState(() {
        _accepted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'This invitation could not be accepted. It may have expired or be for a different email address.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  void _openMyLocalLink() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MyLocalLinkScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Organisation invitation')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(LocalLinkSpacing.lg),
          children: [
            LocalLinkSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalLinkIconBadge(
                    icon: _accepted
                        ? Icons.check_circle_outline
                        : Icons.mail_outline,
                  ),
                  const SizedBox(height: LocalLinkSpacing.md),
                  Text(
                    _accepted ? 'You are in' : 'Join this organisation',
                    style: LocalLinkTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  Text(
                    _accepted
                        ? 'Your LocalLink role has been added. You can manage or view your organisations from My LocalLink.'
                        : 'Accept this invitation to join the organisation on LocalLink.',
                    style: LocalLinkTextStyles.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: LocalLinkSpacing.md),
                    Text(
                      _error!,
                      style: LocalLinkTextStyles.body.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: LocalLinkSpacing.lg),
                  if (_accepted)
                    LocalLinkButton(
                      label: 'Open My LocalLink',
                      icon: Icons.arrow_forward,
                      onPressed: _openMyLocalLink,
                      expand: true,
                    )
                  else
                    LocalLinkButton(
                      label: 'Accept invitation',
                      icon: Icons.check,
                      isLoading: _isAccepting,
                      onPressed: _isAccepting ? null : _accept,
                      expand: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
