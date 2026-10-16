import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/activity_categories.dart';
import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../services/activity_relationships.dart';
import '../services/admin_access_service.dart';
import '../services/business_access_service.dart';
import '../services/organisation_service.dart';
import '../services/organisation_permissions.dart';
import '../theme/app_colors.dart';
import 'package:geolocator/geolocator.dart';
import '../services/address_search_service.dart';
import '../models/address_result.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_surface_card.dart';

@visibleForTesting
bool canShowFixtureActivityOption(Organisation? organisation) {
  return organisation != null &&
      OrganisationPermissions.supportsFixtures(organisation);
}

class CreateOpportunityScreen extends StatefulWidget {
  const CreateOpportunityScreen({
    super.key,
    this.organisation,
    this.group,
    this.initialActivityKind = 'activity',
    this.initialCategory = '',
  });

  final Organisation? organisation;
  final OrganisationGroup? group;
  final String initialActivityKind;
  final String initialCategory;

  @override
  State<CreateOpportunityScreen> createState() =>
      _CreateOpportunityScreenState();
}

class _CreateOpportunityScreenState extends State<CreateOpportunityScreen> {
  final titleController = TextEditingController();

  final descriptionController = TextEditingController();

  final locationController = TextEditingController();
  final opponentController = TextEditingController();
  final prizeDescriptionController = TextEditingController();
  final supportedByBusinessIdController = TextEditingController();
  final supportedByBusinessNameController = TextEditingController();
  final supportedByBusinessImageUrlController = TextEditingController();
  final supportedByBusinessPrizeTextController = TextEditingController();

  final addressService = AddressSearchService();

  List<AddressResult> suggestions = [];

  final ImagePicker picker = ImagePicker();

  File? selectedImage;

  String category = 'Social';

  String repeatType = 'none';
  late String activityKind;
  String audienceScope = 'everyone';
  String fixtureVenue = 'home';
  OrganisationGroup? selectedGroup;

  bool saving = false;

  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  DateTime? challengeClosingDate;
  TimeOfDay? challengeClosingTime;
  DateTime? repeatEndDate;
  double? selectedLatitude;
  double? selectedLongitude;
  bool allowPhotoEntries = true;
  bool canCreateCommunityChallenge = false;
  bool hostChallengeWithBusiness = false;
  bool loadingChallengeAccess = true;
  DocumentSnapshot<Map<String, dynamic>>? challengeHostBusiness;

  @override
  void initState() {
    super.initState();
    activityKind = ActivityRelationshipFields.normaliseActivityKind(
      widget.initialActivityKind,
    );
    final initialCategory = ActivityCategories.normalise(
      widget.initialCategory,
    );
    if (ActivityCategories.values.contains(initialCategory)) {
      category = initialCategory;
    }
    selectedGroup = widget.group;
    if (widget.group != null) {
      audienceScope = 'group';
    }
    final organisation = widget.organisation;
    if (organisation == null) {
      _loadChallengeCreatorAccess();
      return;
    }

    if (activityKind == 'fixture' &&
        !OrganisationPermissions.supportsFixtures(organisation)) {
      activityKind = 'activity';
    }
    category = ActivityCategories.normalise(organisation.category);
    if (!ActivityCategories.values.contains(category)) {
      category = 'Other';
    }
    locationController.text = organisation.location.isNotEmpty
        ? organisation.location
        : organisation.publicLocation;
    selectedLatitude = organisation.latitude;
    selectedLongitude = organisation.longitude;
    _loadChallengeCreatorAccess();
  }

  Future<void> _loadChallengeCreatorAccess() async {
    final organisationCanHost = widget.organisation != null;
    var canCreate = organisationCanHost;
    DocumentSnapshot<Map<String, dynamic>>? business;
    var isAdmin = false;

    try {
      isAdmin = await AdminAccessService().isCurrentUserAdmin();
      business = await BusinessAccessService.loadLinkedChallengeHostBusiness();
      canCreate = canCreate || isAdmin || business != null;
    } catch (_) {
      canCreate = organisationCanHost;
    }

    if (!mounted) return;
    setState(() {
      canCreateCommunityChallenge = canCreate;
      challengeHostBusiness = business;
      hostChallengeWithBusiness = false;
      loadingChallengeAccess = false;
      if (!canCreateCommunityChallenge &&
          activityKind == 'community_challenge') {
        activityKind = 'activity';
      }
    });
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );

    if (picked == null) return;

    setState(() {
      selectedDate = picked;
    });
  }

  Future<void> pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      selectedTime = picked;
    });
  }

  Future<void> pickRepeatEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: repeatEndDate ?? selectedDate ?? DateTime.now(),
      firstDate: selectedDate ?? DateTime.now(),
      lastDate: DateTime(2035),
    );

    if (picked == null) return;

    setState(() {
      repeatEndDate = picked;
    });
  }

  Future<void> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();

      setState(() {
        selectedLatitude = position.latitude;

        selectedLongitude = position.longitude;

        locationController.text =
            '${position.latitude.toStringAsFixed(4)}, '
            '${position.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to get location')));
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    opponentController.dispose();
    prizeDescriptionController.dispose();
    supportedByBusinessIdController.dispose();
    supportedByBusinessNameController.dispose();
    supportedByBusinessImageUrlController.dispose();
    supportedByBusinessPrizeTextController.dispose();
    super.dispose();
  }

  Future<void> pickChallengeClosingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: challengeClosingDate ?? selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );

    if (picked == null) return;

    setState(() {
      challengeClosingDate = picked;
    });
  }

  Future<void> pickChallengeClosingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: challengeClosingTime ?? selectedTime ?? TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      challengeClosingTime = picked;
    });
  }

  DateTime? _challengeClosesAt() {
    final date = challengeClosingDate;
    if (date == null) return null;
    final time = challengeClosingTime ?? const TimeOfDay(hour: 18, minute: 0);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> pickImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return;

    setState(() {
      selectedImage = File(picked.path);
    });
  }

  Future<void> saveOpportunity() async {
    if (titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a title')));

      return;
    }

    if (locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a location')));

      return;
    }

    final eventTimeLabel = selectedTime?.format(context);

    setState(() {
      saving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Please sign in to create an opportunity.');
      }

      final latitude = selectedLatitude;

      final longitude = selectedLongitude;
      final isCommunityChallenge = activityKind == 'community_challenge';
      final challengeClosesAt = _challengeClosesAt();
      final hostedBusiness = hostChallengeWithBusiness
          ? challengeHostBusiness
          : null;
      final hostedBusinessData = hostedBusiness?.data();
      final hostedBusinessName = safeText(
        hostedBusinessData?['businessName'] ?? hostedBusinessData?['name'],
        '',
      );

      if (isCommunityChallenge && challengeClosesAt == null) {
        throw Exception('Please add a closing date for the challenge.');
      }

      if (isCommunityChallenge && !canCreateCommunityChallenge) {
        throw Exception(
          'Community challenges can only be created by LocalLink, authorised businesses or organisation managers.',
        );
      }

      if (isCommunityChallenge &&
          hostChallengeWithBusiness &&
          (hostedBusiness == null || hostedBusinessName.isEmpty)) {
        throw Exception('Unable to confirm the hosting business.');
      }

      if (challengeClosesAt != null &&
          challengeClosesAt.isBefore(DateTime.now())) {
        throw Exception('Challenge closing time must be in the future.');
      }

      String? photoUrl;

      if (selectedImage != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

        final ref = FirebaseStorage.instance.ref().child(
          'opportunityPhotos/${user.uid}/$fileName',
        );

        await ref.putFile(
          selectedImage!,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {'ownerId': user.uid},
          ),
        );

        photoUrl = await ref.getDownloadURL();
      }

      final opportunityRef = FirebaseFirestore.instance
          .collection('opportunities')
          .doc();
      final title = titleController.text.trim();
      final description = descriptionController.text.trim();
      final normalisedCategory = ActivityCategories.normalise(category);
      final organisation = widget.organisation;
      final group = audienceScope == 'group' ? selectedGroup : null;
      if (activityKind == 'fixture' &&
          (organisation == null ||
              !OrganisationPermissions.supportsFixtures(organisation))) {
        throw Exception('Fixtures are not enabled for this organisation.');
      }
      if (organisation != null && audienceScope == 'group' && group == null) {
        throw Exception('Choose a group for this activity.');
      }
      final structuredTags = {
        normalisedCategory,
        if (isCommunityChallenge) ...['Community challenge', 'Challenge'],
        if (organisation != null) ...organisation.subcategories,
        ...title
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((word) => word.length > 2),
      }.where((tag) => tag.toString().trim().isNotEmpty).toList();
      final familyCategory = normalisedCategory == 'Family';

      await opportunityRef.set({
        'title': title,

        'description': description,

        'location': locationController.text.trim(),

        'category': normalisedCategory,

        'tags': structuredTags,

        'audience': familyCategory ? 'Families' : 'All ages',

        'followerAccess': familyCategory ? 'approval_required' : 'open',

        'followerCount': 0,

        'attendeeCount': 0,

        'organiserName':
            organisation?.name ??
            (isCommunityChallenge &&
                    hostChallengeWithBusiness &&
                    hostedBusinessName.isNotEmpty
                ? hostedBusinessName
                : user.displayName ?? 'User'),

        'createdBy': user.uid,

        ...ActivityRelationshipFields.build(
          organisation: organisation,
          group: group,
          audienceScope: audienceScope,
          activityKind: activityKind,
          opponentName: opponentController.text,
          fixtureVenue: fixtureVenue,
        ),

        if (organisation == null) ...{
          'activityAudienceScope': 'everyone',
          'isPubliclyDiscoverable': true,
        },

        if (isCommunityChallenge &&
            organisation == null &&
            hostChallengeWithBusiness &&
            hostedBusiness != null) ...{
          'businessId': hostedBusiness.id,
          'businessName': hostedBusinessName,
          'businessImageUrl': businessCoverImageUrl(hostedBusinessData ?? {}),
          'hostedByType': 'business',
        },

        if (isCommunityChallenge &&
            organisation == null &&
            !hostChallengeWithBusiness) ...{
          'hostedByType': 'locallink',
        },

        if (isCommunityChallenge && organisation != null) ...{
          'hostedByType': widget.group == null ? 'organisation' : 'group',
        },

        'photoUrl': photoUrl,

        if (isCommunityChallenge) ...{
          'challengeClosesAt': Timestamp.fromDate(challengeClosesAt!),
          'allowPhotoEntries': allowPhotoEntries,
          if (prizeDescriptionController.text.trim().isNotEmpty)
            'prizeDescription': prizeDescriptionController.text.trim(),
          if (supportedByBusinessIdController.text.trim().isNotEmpty)
            'supportedByBusinessId': supportedByBusinessIdController.text
                .trim(),
          if (supportedByBusinessNameController.text.trim().isNotEmpty)
            'supportedByBusinessName': supportedByBusinessNameController.text
                .trim(),
          if (supportedByBusinessImageUrlController.text.trim().isNotEmpty)
            'supportedByBusinessImageUrl': supportedByBusinessImageUrlController
                .text
                .trim(),
          if (supportedByBusinessPrizeTextController.text.trim().isNotEmpty)
            'supportedByBusinessPrizeText':
                supportedByBusinessPrizeTextController.text.trim(),
        },

        'latitude': latitude,

        'longitude': longitude,

        'eventDate': selectedDate == null
            ? null
            : Timestamp.fromDate(selectedDate!),

        'eventTime': eventTimeLabel,

        'isActive': true,

        // =========================
        // Recurring Opportunity
        // =========================
        'isRecurring': repeatType != 'none',
        if (repeatType != 'none') 'recurrenceTimeZone': 'Europe/London',

        'repeatType': repeatType,

        'repeatEndDate': repeatEndDate == null
            ? null
            : Timestamp.fromDate(repeatEndDate!),

        'seriesId': opportunityRef.id,

        'occurrenceNumber': 1,

        'previousOccurrenceId': null,

        'nextOccurrenceId': null,

        'seriesStatus': 'active',

        'resumeAfter': null,

        'skipNext': false,

        'cancelledOccurrence': false,

        // =========================
        'reminder24hSent': false,

        'reminder1hSent': false,

        'createdAt': Timestamp.now(),
      });

      // Organisation summaries are updated by the idempotent backend trigger.

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final organisation = widget.organisation;
    final group = selectedGroup;
    final supportsFixtures = canShowFixtureActivityOption(organisation);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Activity'),
        foregroundColor: AppColors.charcoal,
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          LocalLinkSpacing.lg,
          LocalLinkSpacing.sm,
          LocalLinkSpacing.lg,
          LocalLinkSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LocalLinkSectionHeader(
              title: 'Create activity',
              subtitle: organisation == null
                  ? 'Add something people nearby can discover and join.'
                  : 'Creating activity for ${organisation.name}.',
            ),
            const SizedBox(height: LocalLinkSpacing.sm),
            if (organisation != null) ...[
              LocalLinkSurfaceCard(
                elevated: false,
                color: AppColors.activitySoft,
                padding: const EdgeInsets.all(LocalLinkSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: LocalLinkImage(
                        imageUrl: organisation.imageUrl,
                        fallbackIcon: Icons.groups_rounded,
                        accentColor: AppColors.activityBlue,
                        semanticLabel: 'Organisation logo',
                      ),
                    ),
                    const SizedBox(width: LocalLinkSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adding activity for',
                            style: LocalLinkTextStyles.metadata.copyWith(
                              color: AppColors.activityBlue,
                            ),
                          ),
                          const SizedBox(height: LocalLinkSpacing.xxs),
                          Text(
                            organisation.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LocalLinkTextStyles.bodyStrong.copyWith(
                              color: AppColors.activityBlue,
                            ),
                          ),
                          if (group != null) ...[
                            const SizedBox(height: LocalLinkSpacing.xxs),
                            Text(
                              audienceScope == 'group'
                                  ? group.name
                                  : audienceScope == 'organisation'
                                  ? 'Whole organisation'
                                  : 'Public on LocalLink',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LocalLinkTextStyles.metadata.copyWith(
                                color: AppColors.activityBlue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LocalLinkSpacing.md),
            ],
            if (organisation != null) ...[
              _AudienceSection(
                organisation: organisation,
                fixedGroup: widget.group,
                selectedScope: audienceScope,
                selectedGroup: selectedGroup,
                onChanged: (scope, group) => setState(() {
                  audienceScope = scope;
                  selectedGroup = scope == 'group' ? group : null;
                }),
              ),
              const SizedBox(height: LocalLinkSpacing.md),
            ],
            LocalLinkFormSection(
              title: 'Activity details',
              helperText: 'Keep the name clear and the description useful.',
              children: [
                LocalLinkFormField(
                  controller: titleController,
                  label: organisation == null
                      ? 'Activity name'
                      : 'Session name',
                  hintText: 'e.g. Saturday morning activity',
                ),
                const SizedBox(height: LocalLinkSpacing.sm),
                LocalLinkFormField(
                  controller: descriptionController,
                  label: 'Description',
                  hintText: 'What should people know before they come?',
                  maxLines: 4,
                ),
                const SizedBox(height: LocalLinkSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: ActivityCategories.values.contains(category)
                      ? category
                      : 'Other',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ActivityCategories.values
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      category = value;
                    });
                  },
                ),
                const SizedBox(height: LocalLinkSpacing.md),
                Text('Type', style: LocalLinkTextStyles.label),
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xs,
                  children: [
                    _KindChoice(
                      label: 'Activity',
                      value: 'activity',
                      selectedValue: activityKind,
                      onSelected: (value) =>
                          setState(() => activityKind = value),
                    ),
                    _KindChoice(
                      label: 'Session',
                      value: 'session',
                      selectedValue: activityKind,
                      onSelected: (value) =>
                          setState(() => activityKind = value),
                    ),
                    _KindChoice(
                      label: 'Event',
                      value: 'event',
                      selectedValue: activityKind,
                      onSelected: (value) =>
                          setState(() => activityKind = value),
                    ),
                    if (canCreateCommunityChallenge)
                      _KindChoice(
                        label: 'Community challenge',
                        value: 'community_challenge',
                        selectedValue: activityKind,
                        onSelected: (value) =>
                            setState(() => activityKind = value),
                      ),
                    if (supportsFixtures)
                      _KindChoice(
                        label: 'Fixture',
                        value: 'fixture',
                        selectedValue: activityKind,
                        onSelected: (value) =>
                            setState(() => activityKind = value),
                      ),
                  ],
                ),
                if (!loadingChallengeAccess &&
                    !canCreateCommunityChallenge) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Text(
                    'Community challenges are currently created by LocalLink, authorised businesses and organisation managers.',
                    style: LocalLinkTextStyles.metadata,
                  ),
                ],
                if (activityKind == 'fixture') ...[
                  const SizedBox(height: LocalLinkSpacing.md),
                  LocalLinkFormField(
                    controller: opponentController,
                    label: 'Opponent',
                    hintText: 'Visiting team or group',
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  Text('Venue', style: LocalLinkTextStyles.label),
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Wrap(
                    spacing: LocalLinkSpacing.xs,
                    runSpacing: LocalLinkSpacing.xs,
                    children: [
                      _KindChoice(
                        label: 'Home',
                        value: 'home',
                        selectedValue: fixtureVenue,
                        onSelected: (value) =>
                            setState(() => fixtureVenue = value),
                      ),
                      _KindChoice(
                        label: 'Away',
                        value: 'away',
                        selectedValue: fixtureVenue,
                        onSelected: (value) =>
                            setState(() => fixtureVenue = value),
                      ),
                      _KindChoice(
                        label: 'Neutral',
                        value: 'neutral',
                        selectedValue: fixtureVenue,
                        onSelected: (value) =>
                            setState(() => fixtureVenue = value),
                      ),
                    ],
                  ),
                ],
              ],
            ),

            const SizedBox(height: LocalLinkSpacing.md),

            LocalLinkFormSection(
              title: 'Where it happens',
              helperText: 'Use a public place name or approximate location.',
              children: [
                LocalLinkFormField(
                  controller: locationController,
                  label: 'Location',
                  hintText: 'Community hall, park or venue',
                  onChanged: (value) async {
                    final results = await addressService.search(value);

                    if (!mounted) return;

                    setState(() {
                      suggestions = results;
                    });
                  },
                ),

                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  LocalLinkSurfaceCard(
                    elevated: false,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: suggestions.map((suggestion) {
                        return ListTile(
                          title: Text(
                            suggestion.description,
                            style: LocalLinkTextStyles.body,
                          ),
                          onTap: () async {
                            final coords = await addressService.getCoordinates(
                              suggestion.placeId,
                            );

                            if (!mounted) return;

                            setState(() {
                              selectedLatitude = coords?['lat'];

                              selectedLongitude = coords?['lng'];

                              locationController.text = suggestion.description;

                              suggestions = [];
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: LocalLinkSpacing.sm),
                LocalLinkButton(
                  label: 'Use current location',
                  icon: Icons.my_location_rounded,
                  variant: LocalLinkButtonVariant.secondary,
                  onPressed: getCurrentLocation,
                  expand: true,
                ),
              ],
            ),

            const SizedBox(height: LocalLinkSpacing.md),

            LocalLinkFormSection(
              title: 'When',
              helperText: activityKind == 'community_challenge'
                  ? 'Add the start date and closing point.'
                  : 'Add the first date and how often it repeats.',
              children: [
                LocalLinkDateTimeRow(
                  label: 'Date',
                  value: selectedDate == null
                      ? 'Select date'
                      : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                  onTap: pickDate,
                ),
                const SizedBox(height: LocalLinkSpacing.sm),
                LocalLinkDateTimeRow(
                  label: 'Time',
                  value: selectedTime == null
                      ? 'Select time'
                      : selectedTime!.format(context),
                  onTap: pickTime,
                ),
                const SizedBox(height: LocalLinkSpacing.md),
                Text('Repeat', style: LocalLinkTextStyles.label),
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xs,
                  children: [
                    _RepeatChoice(
                      label: 'None',
                      value: 'none',
                      selectedValue: repeatType,
                      onSelected: (value) => setState(() => repeatType = value),
                    ),
                    _RepeatChoice(
                      label: 'Daily',
                      value: 'daily',
                      selectedValue: repeatType,
                      onSelected: (value) => setState(() => repeatType = value),
                    ),
                    _RepeatChoice(
                      label: 'Weekly',
                      value: 'weekly',
                      selectedValue: repeatType,
                      onSelected: (value) => setState(() => repeatType = value),
                    ),
                    _RepeatChoice(
                      label: 'Fortnightly',
                      value: 'fortnightly',
                      selectedValue: repeatType,
                      onSelected: (value) => setState(() => repeatType = value),
                    ),
                    _RepeatChoice(
                      label: 'Monthly',
                      value: 'monthly',
                      selectedValue: repeatType,
                      onSelected: (value) => setState(() => repeatType = value),
                    ),
                  ],
                ),
                if (repeatType != 'none') ...[
                  const SizedBox(height: LocalLinkSpacing.md),
                  LocalLinkDateTimeRow(
                    label: 'Repeat until',
                    value: repeatEndDate == null
                        ? 'Optional'
                        : '${repeatEndDate!.day}/${repeatEndDate!.month}/${repeatEndDate!.year}',
                    onTap: pickRepeatEndDate,
                  ),
                ],
                if (activityKind == 'community_challenge') ...[
                  const SizedBox(height: LocalLinkSpacing.md),
                  LocalLinkDateTimeRow(
                    label: 'Entries close',
                    value: challengeClosingDate == null
                        ? 'Select closing date'
                        : '${challengeClosingDate!.day}/${challengeClosingDate!.month}/${challengeClosingDate!.year}',
                    onTap: pickChallengeClosingDate,
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  LocalLinkDateTimeRow(
                    label: 'Closing time',
                    value: challengeClosingTime == null
                        ? '6:00 PM'
                        : challengeClosingTime!.format(context),
                    onTap: pickChallengeClosingTime,
                  ),
                ],
              ],
            ),

            if (activityKind == 'community_challenge') ...[
              const SizedBox(height: LocalLinkSpacing.md),
              LocalLinkFormSection(
                title: 'Challenge',
                helperText:
                    'Prize and supporting business details are optional.',
                children: [
                  if (challengeHostBusiness != null &&
                      widget.organisation == null) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: hostChallengeWithBusiness,
                      title: Text(
                        'Host as ${safeText(challengeHostBusiness!.data()?['businessName'] ?? challengeHostBusiness!.data()?['name'], 'your business')}',
                      ),
                      subtitle: const Text(
                        'Use this when the business is running and managing the challenge.',
                      ),
                      onChanged: (value) =>
                          setState(() => hostChallengeWithBusiness = value),
                    ),
                    const SizedBox(height: LocalLinkSpacing.sm),
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: allowPhotoEntries,
                    title: const Text('Allow photo entries'),
                    onChanged: (value) =>
                        setState(() => allowPhotoEntries = value),
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  LocalLinkFormField(
                    controller: prizeDescriptionController,
                    label: 'Prize description',
                    hintText: 'Optional, for example £25 pet shop voucher',
                    maxLines: 2,
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  LocalLinkFormField(
                    controller: supportedByBusinessIdController,
                    label: 'Supporting business ID',
                    hintText: 'Optional LocalLink business document ID',
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  LocalLinkFormField(
                    controller: supportedByBusinessNameController,
                    label: 'Supporting business name',
                    hintText: 'Optional',
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  LocalLinkFormField(
                    controller: supportedByBusinessImageUrlController,
                    label: 'Supporting business image URL',
                    hintText: 'Optional',
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  LocalLinkFormField(
                    controller: supportedByBusinessPrizeTextController,
                    label: 'Supported prize text',
                    hintText: 'Optional, for example Prize: £25 voucher',
                    maxLines: 2,
                  ),
                ],
              ),
            ],

            const SizedBox(height: LocalLinkSpacing.md),

            LocalLinkFormSection(
              title: 'Photo',
              helperText:
                  'Optional, but useful for making the activity stand out.',
              children: [
                Material(
                  color: AppColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: pickImage,
                    child: SizedBox(
                      height: 176,
                      width: double.infinity,
                      child: selectedImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.image_outlined,
                                  color: AppColors.activityBlue,
                                  size: 38,
                                ),
                                const SizedBox(height: LocalLinkSpacing.xs),
                                Text(
                                  'Add photo',
                                  style: LocalLinkTextStyles.bodyStrong,
                                ),
                                const SizedBox(height: LocalLinkSpacing.xxs),
                                Text(
                                  'Optional',
                                  style: LocalLinkTextStyles.metadata,
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(
                                LocalLinkRadius.md,
                              ),
                              child: Image.file(
                                selectedImage!,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: LocalLinkSpacing.xl),

            LocalLinkButton(
              label: saving
                  ? 'Creating...'
                  : activityKind == 'community_challenge'
                  ? 'Create challenge'
                  : 'Create activity',
              icon: Icons.add_circle_outline_rounded,
              isLoading: saving,
              onPressed: saving ? null : saveOpportunity,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RepeatChoice extends StatelessWidget {
  const _RepeatChoice({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = selectedValue == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: AppColors.activityBlue.withValues(alpha: 0.14),
      backgroundColor: AppColors.elevatedSurface,
      labelStyle: LocalLinkTextStyles.label.copyWith(
        color: selected ? AppColors.activityBlue : AppColors.textMuted,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.activityBlue.withValues(alpha: 0.30)
            : AppColors.border,
      ),
    );
  }
}

class _KindChoice extends _RepeatChoice {
  const _KindChoice({
    required super.label,
    required super.value,
    required super.selectedValue,
    required super.onSelected,
  });
}

class _AudienceSection extends StatelessWidget {
  _AudienceSection({
    required this.organisation,
    required this.fixedGroup,
    required this.selectedScope,
    required this.selectedGroup,
    required this.onChanged,
  }) : _service = OrganisationService();

  final Organisation organisation;
  final OrganisationGroup? fixedGroup;
  final String selectedScope;
  final OrganisationGroup? selectedGroup;
  final void Function(String scope, OrganisationGroup? group) onChanged;
  final OrganisationService _service;

  @override
  Widget build(BuildContext context) {
    final fixed = fixedGroup;
    if (fixed != null) {
      return LocalLinkFormSection(
        title: 'Who is this for?',
        children: [
          _AudienceChoice(
            title: 'Specific group',
            subtitle: fixed.name,
            selected: true,
            onTap: () => onChanged('group', fixed),
          ),
        ],
      );
    }

    return StreamBuilder<List<OrganisationGroup>>(
      stream: _service.watchGroups(organisation.id),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const <OrganisationGroup>[];
        return LocalLinkFormSection(
          title: 'Who is this for?',
          children: [
            _AudienceChoice(
              title: 'Everyone',
              subtitle: 'Public on LocalLink',
              selected: selectedScope == 'everyone',
              onTap: () => onChanged('everyone', null),
            ),
            const SizedBox(height: LocalLinkSpacing.sm),
            _AudienceChoice(
              title: 'Whole organisation',
              subtitle: organisation.name,
              selected: selectedScope == 'organisation',
              onTap: () => onChanged('organisation', null),
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: LocalLinkSpacing.sm),
              _AudienceChoice(
                title: 'Specific group',
                subtitle: selectedGroup?.name ?? 'Choose group',
                selected: selectedScope == 'group',
                onTap: () => onChanged('group', selectedGroup ?? groups.first),
              ),
              if (selectedScope == 'group') ...[
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xs,
                  children: [
                    for (final group in groups)
                      _KindChoice(
                        label: group.name,
                        value: group.id,
                        selectedValue: selectedGroup?.id ?? '',
                        onSelected: (_) => onChanged('group', group),
                      ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _AudienceChoice extends StatelessWidget {
  const _AudienceChoice({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      color: selected ? AppColors.activitySoft : AppColors.card,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: AppColors.activityBlue,
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LocalLinkTextStyles.bodyStrong),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(subtitle, style: LocalLinkTextStyles.metadata),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
