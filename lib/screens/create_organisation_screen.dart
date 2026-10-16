import 'package:flutter/material.dart';

import '../models/address_result.dart';
import '../models/organisation.dart';
import '../services/address_search_service.dart';
import '../services/organisation_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_chip.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_surface_card.dart';
import 'my_locallink_screen.dart';
import 'organisation_detail_screen.dart';
import 'organisation_management_screen.dart';

const organisationCreationCategories = [
  'Sport & fitness',
  'Community',
  'Children & families',
  'Social',
  'Hobbies & interests',
  'Music & dance',
  'Education',
  'Charity & volunteering',
  'Faith & community',
  'Other',
];

class CreateOrganisationScreen extends StatefulWidget {
  const CreateOrganisationScreen({
    super.key,
    this.organisationService,
    this.addressSearchService,
  });

  final OrganisationService? organisationService;
  final AddressSearchService? addressSearchService;

  @override
  State<CreateOrganisationScreen> createState() =>
      _CreateOrganisationScreenState();
}

class _CreateOrganisationScreenState extends State<CreateOrganisationScreen> {
  OrganisationService? _service;
  AddressSearchService? _addressSearchService;
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = organisationCreationCategories.first;
  List<AddressResult> _locationSuggestions = [];
  bool _searchingLocation = false;
  int _locationSearchRequest = 0;
  double? _selectedLatitude;
  double? _selectedLongitude;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  OrganisationService get _organisationService =>
      widget.organisationService ?? (_service ??= OrganisationService());

  AddressSearchService get _addressSearch =>
      widget.addressSearchService ??
      (_addressSearchService ??= AddressSearchService());

  Future<void> _searchLocations(String value) async {
    final query = value.trim();
    final request = ++_locationSearchRequest;
    _selectedLatitude = null;
    _selectedLongitude = null;

    if (query.length < 3) {
      setState(() {
        _locationSuggestions = [];
        _searchingLocation = false;
      });
      return;
    }

    setState(() => _searchingLocation = true);
    try {
      final results = await _addressSearch.search(query);
      if (!mounted || request != _locationSearchRequest) return;
      setState(() {
        _locationSuggestions = results;
        _searchingLocation = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Organisation location search failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || request != _locationSearchRequest) return;
      setState(() {
        _locationSuggestions = [];
        _searchingLocation = false;
      });
    }
  }

  Future<void> _selectLocation(AddressResult suggestion) async {
    final request = ++_locationSearchRequest;
    setState(() {
      _locationController.text = suggestion.description;
      _locationSuggestions = [];
      _searchingLocation = true;
    });

    try {
      final coordinates = await _addressSearch.getCoordinates(
        suggestion.placeId,
      );
      if (!mounted || request != _locationSearchRequest) return;
      setState(() {
        _selectedLatitude = coordinates?['lat'];
        _selectedLongitude = coordinates?['lng'];
        _searchingLocation = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Organisation location coordinates failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || request != _locationSearchRequest) return;
      setState(() => _searchingLocation = false);
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    final location = _locationController.text.trim();
    if (name.isEmpty || location.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add a name and location.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final ref = await _organisationService.createSelfServiceOrganisation(
        name: name,
        category: _category,
        location: location,
        description: _descriptionController.text,
        latitude: _selectedLatitude,
        longitude: _selectedLongitude,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _OrganisationCreatedScreen(
            organisation: Organisation.fromMap(ref.id, {
              'name': name,
              'description': _descriptionController.text.trim(),
              'category': _category,
              'area': location,
              'publicLocation': location,
              'location': location,
              'latitude': _selectedLatitude,
              'longitude': _selectedLongitude,
              'ownerId': _organisationService.currentUserId,
              'adminUserIds': [_organisationService.currentUserId],
              'listingOwnershipStatus': 'claimed',
              'claimStatus': 'approved',
              'isActive': true,
            }),
          ),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group or organisation created.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Organisation creation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This could not be created.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Group or organisation'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const LocalLinkSectionHeader(
            title: 'Create your club, group or organisation',
            subtitle:
                'Add the details people need to find and understand your community.',
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkFormSection(
            title: 'Basics',
            helperText: 'These details appear on your LocalLink page.',
            children: [
              LocalLinkFormField(
                controller: _nameController,
                label: 'Name',
                hintText: 'Your club, group or organisation',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              Text('Category', style: LocalLinkTextStyles.metadata),
              const SizedBox(height: LocalLinkSpacing.xs),
              Wrap(
                spacing: LocalLinkSpacing.xs,
                runSpacing: LocalLinkSpacing.xs,
                children: [
                  for (final category in organisationCreationCategories)
                    LocalLinkChip(
                      label: category,
                      selected: _category == category,
                      accentColor: AppColors.activityBlue,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _locationController,
                label: 'Location',
                hintText: 'Start typing a town, venue or area',
                onChanged: _searchLocations,
              ),
              if (_searchingLocation) ...[
                const SizedBox(height: LocalLinkSpacing.xs),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_locationSuggestions.isNotEmpty) ...[
                const SizedBox(height: LocalLinkSpacing.xs),
                LocalLinkSurfaceCard(
                  elevated: false,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final suggestion in _locationSuggestions)
                        ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            suggestion.description,
                            style: LocalLinkTextStyles.body,
                          ),
                          onTap: () => _selectLocation(suggestion),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: _descriptionController,
                label: 'Short description',
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          LocalLinkButton(
            label: _saving ? 'Creating...' : 'Create',
            icon: Icons.add_rounded,
            onPressed: _saving ? null : _create,
            isLoading: _saving,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _OrganisationCreatedScreen extends StatelessWidget {
  const _OrganisationCreatedScreen({required this.organisation});

  final Organisation organisation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Created'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalLinkSurfaceCard(
                padding: const EdgeInsets.all(LocalLinkSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.activityBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.activityBlue,
                      ),
                    ),
                    const SizedBox(height: LocalLinkSpacing.md),
                    Text(
                      'Your organisation is live',
                      style: LocalLinkTextStyles.screenTitle,
                    ),
                    const SizedBox(height: LocalLinkSpacing.xs),
                    Text(
                      '${organisation.name} now has a home on LocalLink.',
                      style: LocalLinkTextStyles.secondary,
                    ),
                    const SizedBox(height: LocalLinkSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(LocalLinkSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.elevatedSurface,
                        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.72),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            organisation.name,
                            style: LocalLinkTextStyles.cardTitle,
                          ),
                          const SizedBox(height: LocalLinkSpacing.xxs),
                          Text(
                            [
                              organisation.category,
                              organisation.publicLocation,
                            ].where((item) => item.isNotEmpty).join(' · '),
                            style: LocalLinkTextStyles.metadata,
                          ),
                          if (organisation.description.isNotEmpty) ...[
                            const SizedBox(height: LocalLinkSpacing.sm),
                            Text(
                              organisation.description,
                              style: LocalLinkTextStyles.body,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              LocalLinkButton(
                label: 'View organisation',
                icon: Icons.visibility_outlined,
                expand: true,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrganisationDetailScreen(
                        organisationId: organisation.id,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkButton(
                label: 'Set up your organisation',
                icon: Icons.tune_outlined,
                variant: LocalLinkButtonVariant.secondary,
                expand: true,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrganisationManagementScreen(
                        organisation: organisation,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyLocalLinkScreen(),
                    ),
                  );
                },
                child: const Text('Back to My LocalLink'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
