import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/address_result.dart';
import '../services/analytics_service.dart';
import '../services/address_search_service.dart';
import '../services/auth_required_action.dart';
import '../services/booking_messaging_service.dart';
import '../services/community_help_share_service.dart';
import '../services/community_help_lifecycle.dart';
import '../services/community_help_location.dart';
import '../services/community_help_following_service.dart';
import '../services/community_help_ownership.dart';
import '../services/local_discovery_filters.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/community_help_own_reports.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_surface_card.dart';
import 'booking_conversation_screen.dart';
import 'listing_claim_request_screen.dart';

enum _CommunityHelpType { lostFound, freeItem }

const _lostFoundCategories = [
  'Pet',
  'Keys',
  'Phone',
  'Wallet',
  'Bike / scooter',
  'Bag',
  'Other',
];

bool _isPetCategory(String category) => category.trim().toLowerCase() == 'pet';

class CommunityHelpInitialDraft {
  const CommunityHelpInitialDraft({
    required this.type,
    required this.mode,
    this.itemCategory = '',
    this.petType = '',
  });

  const CommunityHelpInitialDraft.missingPet({this.petType = ''})
    : type = 'lost_found',
      mode = 'lost',
      itemCategory = 'Pet';

  final String type;
  final String mode;
  final String itemCategory;
  final String petType;
}

Color _communityAccent({required String mode, required String type}) {
  if (type == 'free_item') return AppColors.communityTeal;
  if (mode == 'found') return AppColors.serviceGreen;
  return AppColors.lost;
}

IconData _communityFallbackIcon({
  required String mode,
  required String type,
  required String category,
}) {
  if (type == 'free_item') return Icons.card_giftcard_outlined;
  if (_isPetCategory(category)) return Icons.pets_outlined;
  return mode == 'lost' ? Icons.search_outlined : Icons.inventory_2_outlined;
}

class PostServiceRequestScreen extends StatefulWidget {
  const PostServiceRequestScreen({
    super.key,
    this.initialPostId,
    this.initialDraft,
    this.initialFocusNearby = false,
  });

  final String? initialPostId;
  final CommunityHelpInitialDraft? initialDraft;
  final bool initialFocusNearby;

  @override
  State<PostServiceRequestScreen> createState() =>
      _PostServiceRequestScreenState();
}

class _PostServiceRequestScreenState extends State<PostServiceRequestScreen> {
  final _nearbySectionKey = GlobalKey();
  final titleController = TextEditingController();
  final petTypeController = TextEditingController();
  final descriptionController = TextEditingController();
  final locationController = TextEditingController();
  final timingController = TextEditingController();
  final collectionController = TextEditingController();

  final ImagePicker picker = ImagePicker();
  final AddressSearchService addressService = AddressSearchService();

  _CommunityHelpType? helpType;
  File? selectedImage;
  List<AddressResult> locationSuggestions = [];
  bool isSaving = false;
  bool isLocating = false;
  String lostFoundMode = 'lost';
  String freeItemMode = 'wanted';
  String itemCategory = _lostFoundCategories.first;
  DateTime? observedAt;
  bool observedDateOnly = false;
  double? selectedLatitude;
  double? selectedLongitude;
  String? selectedPlaceId;
  String locationSource = 'manual';
  int _locationSearchSerial = 0;

  bool get _isLostFound => helpType == _CommunityHelpType.lostFound;
  bool get _isFreeItem => helpType == _CommunityHelpType.freeItem;

  @override
  void dispose() {
    titleController.dispose();
    petTypeController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    timingController.dispose();
    collectionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    final postId = widget.initialPostId?.trim();
    if (postId == null || postId.isEmpty) {
      final draft = widget.initialDraft;
      if (draft != null) _applyInitialDraft(draft);
      if (widget.initialFocusNearby) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nearbyContext = _nearbySectionKey.currentContext;
          if (nearbyContext != null) {
            Scrollable.ensureVisible(
              nearbyContext,
              duration: const Duration(milliseconds: 250),
              alignment: 0.05,
            );
          }
        });
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialPost(postId);
    });
  }

  void _applyInitialDraft(CommunityHelpInitialDraft draft) {
    final type = draft.type.trim();
    final mode = draft.mode.trim();
    helpType = type == 'free_item'
        ? _CommunityHelpType.freeItem
        : _CommunityHelpType.lostFound;
    lostFoundMode = mode == 'found' ? 'found' : 'lost';
    freeItemMode = mode == 'wanted' ? 'wanted' : 'offering';
    if (_lostFoundCategories.contains(draft.itemCategory)) {
      itemCategory = draft.itemCategory;
    }
    if (_isPetCategory(itemCategory) && draft.petType.trim().isNotEmpty) {
      petTypeController.text = draft.petType.trim();
    }
  }

  void _startLostFoundReport(String mode) {
    setState(() {
      helpType = _CommunityHelpType.lostFound;
      lostFoundMode = mode;
      titleController.clear();
      petTypeController.clear();
      descriptionController.clear();
      locationController.clear();
      timingController.clear();
      collectionController.clear();
      observedAt = null;
      observedDateOnly = false;
      selectedImage = null;
      locationSuggestions = [];
      selectedLatitude = null;
      selectedLongitude = null;
      selectedPlaceId = null;
      locationSource = 'manual';
      itemCategory = _lostFoundCategories.first;
    });
  }

  void _setLostFoundMode(String value) {
    // Correcting the report type should keep the details already entered.
    setState(() => lostFoundMode = value);
  }

  Future<void> _searchLocations(String query) async {
    final trimmed = query.trim();

    setState(() {
      selectedLatitude = null;
      selectedLongitude = null;
      selectedPlaceId = null;
      locationSource = 'manual';
    });

    final serial = ++_locationSearchSerial;
    if (trimmed.length < 3) {
      setState(() => locationSuggestions = []);
      return;
    }

    final results = await addressService.search(trimmed);
    if (!mounted || serial != _locationSearchSerial) return;

    setState(() => locationSuggestions = results.take(5).toList());
  }

  Future<void> _selectLocationSuggestion(AddressResult suggestion) async {
    final coords = await addressService.getCoordinates(suggestion.placeId);
    if (!mounted) return;

    if (coords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not locate that place.')),
      );
      return;
    }

    var publicArea = 'Selected area';
    try {
      publicArea = await addressService.getPublicAreaLabel(suggestion.placeId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      selectedLatitude = _softCoordinate(coords['lat']!);
      selectedLongitude = _softCoordinate(coords['lng']!);
      selectedPlaceId = null;
      locationSource = 'place_search_approximate';
      locationController.text = publicArea;
      locationSuggestions = [];
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => isLocating = true);

    try {
      final position = await LocationService().getCurrentLocation();
      if (!mounted) return;

      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location is unavailable right now.')),
        );
        return;
      }

      final publicLabel = await _publicLabelFor(position);
      if (!mounted) return;

      setState(() {
        selectedLatitude = _softCoordinate(position.latitude);
        selectedLongitude = _softCoordinate(position.longitude);
        selectedPlaceId = null;
        locationSource = 'current_location_approximate';
        locationController.text = publicLabel;
        locationSuggestions = [];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not get your location.')),
      );
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
    );

    if (!mounted || picked == null) return;

    setState(() {
      selectedImage = File(picked.path);
    });
  }

  Future<void> _pickObservedAt() async {
    final now = DateTime.now();
    final current = observedAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: CommunityHelpLifecycle.firstSelectableObservedDate(now),
      lastDate: CommunityHelpLifecycle.latestSelectableObservedAt(now),
      helpText: lostFoundMode == 'found'
          ? 'When did you find it?'
          : 'When was it last seen?',
    );
    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current.isAfter(now) ? now : current),
      helpText: lostFoundMode == 'found' ? 'Time found' : 'Time last seen',
    );
    if (!mounted) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    final normalised = CommunityHelpLifecycle.normaliseObservedAt(
      selected,
      now,
    );
    final dateOnly = time == null;

    setState(() {
      observedAt = normalised;
      observedDateOnly = dateOnly;
      timingController.text = CommunityHelpLifecycle.observedAtText({
        'observedAt': observedAt,
        if (dateOnly) 'observedDateOnly': true,
      }, now);
    });
  }

  Future<String?> _uploadImage(String userId) async {
    if (selectedImage == null) return null;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child(
      'communityHelpPhotos/$userId/$fileName',
    );

    await ref.putFile(
      selectedImage!,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'ownerId': userId},
      ),
    );

    return ref.getDownloadURL();
  }

  Future<String?> _uploadSightingImage(String userId, File image) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_sighting.jpg';
    final ref = FirebaseStorage.instance.ref().child(
      'communityHelpPhotos/$userId/$fileName',
    );

    await ref.putFile(
      image,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'ownerId': userId, 'purpose': 'sighting'},
      ),
    );

    return ref.getDownloadURL();
  }

  Future<void> _publish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to post community help.')),
      );
      return;
    }

    final type = helpType;
    final title = titleController.text.trim();
    final petType = petTypeController.text.trim();
    final description = descriptionController.text.trim();
    final location = locationController.text.trim();
    final timing = _isLostFound
        ? CommunityHelpLifecycle.observedAtText({
            'observedAt': observedAt,
            if (observedDateOnly) 'observedDateOnly': true,
          }, DateTime.now())
        : timingController.text.trim();
    final collection = collectionController.text.trim();

    if (type == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose lost/found or free items first.')),
      );
      return;
    }

    if (title.isEmpty || description.isEmpty || location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add the item, details and public area.')),
      );
      return;
    }

    if (_isLostFound &&
        itemCategory == CommunityHelpLifecycle.petCategory &&
        petType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add the pet type, such as dog or cat.')),
      );
      return;
    }

    if (_isLostFound && observedAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add when this was last seen or found.')),
      );
      return;
    }

    if (selectedLatitude == null || selectedLongitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a location suggestion or use current location.',
          ),
        ),
      );
      return;
    }

    if (_isFreeItem && collection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add collection or delivery information.'),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final photoUrl = await _uploadImage(user.uid);
      final now = DateTime.now();
      final mode = _isLostFound ? lostFoundMode : freeItemMode;
      final typeName = _isLostFound ? 'lost_found' : 'free_item';
      final category = _isLostFound ? itemCategory : 'Free item';
      final expiresAt = CommunityHelpLifecycle.expiresAt(
        now: now,
        type: typeName,
        mode: mode,
        itemCategory: category,
      );

      await FirebaseFirestore.instance.collection('communityHelpPosts').add({
        'createdBy': user.uid,
        'createdByName': user.displayName ?? 'LocalLink member',
        'type': typeName,
        'mode': mode,
        'title': title,
        'description': description,
        'location': CommunityHelpLocation.safeInputLabel(location),
        'publicLocation': CommunityHelpLocation.safeInputLabel(location),
        'locationPrecision': 'approximate',
        'locationSource': locationSource,
        'approxLatitude': selectedLatitude,
        'approxLongitude': selectedLongitude,
        'discoveryRadiusMiles':
            CommunityHelpLifecycle.defaultDiscoveryRadiusMiles(
              type: typeName,
              mode: mode,
              itemCategory: category,
            ),
        'timing': timing,
        'eventDateText': timing,
        if (_isLostFound && observedDateOnly) 'observedDateOnly': true,
        if (_isLostFound && observedAt != null)
          'observedAt': Timestamp.fromDate(observedAt!),
        if (_isLostFound && lostFoundMode == 'lost' && observedAt != null)
          'lastSeenAt': Timestamp.fromDate(observedAt!),
        if (_isLostFound && lostFoundMode == 'found' && observedAt != null)
          'foundAt': Timestamp.fromDate(observedAt!),
        'itemCategory': category,
        if (category == CommunityHelpLifecycle.petCategory) 'petType': petType,
        'keywords': CommunityHelpLifecycle.keywordsFor(
          '$title $petType $description $category $location',
        ),
        'collectionDetails': _isFreeItem ? collection : '',
        'photoUrl': photoUrl,
        'isFree': _isFreeItem,
        'allowsPayment': false,
        'status': CommunityHelpLifecycle.activeStatus,
        'lifecycleKind': CommunityHelpLifecycle.lifecycleKind(
          type: typeName,
          mode: mode,
          itemCategory: category,
        ),
        'renewalCount': 0,
        'expiryReminderAt': Timestamp.fromDate(
          CommunityHelpLifecycle.expiryReminderAt(expiresAt),
        ),
        'expiryReminderStatus': 'pending',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your community help post is live.')),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not share this. Try again.')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  double _softCoordinate(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  Future<String> _publicLabelFor(dynamic position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      for (final place in placemarks) {
        final label =
            [place.subLocality, place.locality, place.subAdministrativeArea]
                .whereType<String>()
                .map((value) => value.trim())
                .firstWhere((value) => value.isNotEmpty, orElse: () => '');

        if (label.isNotEmpty && !_looksLikePreciseAddress(label)) {
          return label;
        }
      }

      final fallback = placemarks.isEmpty ? '' : placemarks.first.locality;
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
    } catch (_) {
      // Fall through to a non-precise default below.
    }

    return 'Near my current area';
  }

  bool _looksLikePreciseAddress(String label) {
    return RegExp(r'^\d+[a-zA-Z]?\b').hasMatch(label.trim());
  }

  Future<void> _markResolved(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final type = data['type'] as String? ?? 'lost_found';
    final mode = data['mode'] as String? ?? 'lost';
    final category = data['itemCategory'] as String? ?? 'Other';
    final reason = CommunityHelpLifecycle.resolveReason(
      type: type,
      mode: mode,
      itemCategory: category,
      freeItemWanted: mode == CommunityHelpLifecycle.wantedMode,
    );
    final closingUpdate = await _askForClosingUpdate(reason);
    if (!mounted) return;

    await doc.reference.update({
      'status': CommunityHelpLifecycle.resolvedStatus,
      'resolvedReason': reason,
      'isActive': false,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
      'expiryReminderStatus': 'cancelled',
      if (closingUpdate != null && closingUpdate.isNotEmpty)
        'closingUpdate': closingUpdate,
    });

    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Great news — marked as ${_resolvedToastLabel(reason)}.'),
      ),
    );
  }

  Future<String?> _askForClosingUpdate(String reason) async {
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _ClosingUpdateDialog(title: 'Mark as ${_resolvedToastLabel(reason)}'),
    );
  }

  Future<void> _renewPost(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final type = data['type'] as String? ?? 'lost_found';
    final mode = data['mode'] as String? ?? 'lost';
    final category = data['itemCategory'] as String? ?? 'Other';
    final expiresAt = CommunityHelpLifecycle.expiresAt(
      now: DateTime.now(),
      type: type,
      mode: mode,
      itemCategory: category,
    );

    await doc.reference.update({
      'status': CommunityHelpLifecycle.activeStatus,
      'isActive': true,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'expiryReminderAt': Timestamp.fromDate(
        CommunityHelpLifecycle.expiryReminderAt(expiresAt),
      ),
      'expiryReminderStatus': 'pending',
      'lastRenewedAt': FieldValue.serverTimestamp(),
      'renewalCount': FieldValue.increment(1),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kept active for the community.')),
    );
  }

  String _resolvedToastLabel(String reason) {
    switch (reason) {
      case 'returned':
        return 'returned';
      case 'collected':
        return 'collected';
      case 'no_longer_needed':
        return 'no longer needed';
      case 'reunited':
        return 'reunited';
      default:
        return 'found';
    }
  }

  Future<void> _sendPrivateReply(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String message,
    String? sightingPhotoUrl,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to reply privately.')),
      );
      return;
    }

    final data = doc.data() ?? {};
    final ownerId = resolveCommunityHelpOwnerId(data);
    if (ownerId == null || ownerId == user.uid) return;

    late final String conversationId;
    try {
      conversationId = await BookingMessagingService()
          .createCommunityHelpConversation(
            postId: doc.id,
            text: message,
            sightingPhotoUrl: sightingPhotoUrl,
          );
      await LocalLinkAnalytics.instance.messageStarted(
        source: 'community_help_detail',
        type: sightingPhotoUrl == null ? 'community_help_reply' : 'sighting',
      );
      if (sightingPhotoUrl != null) {
        await LocalLinkAnalytics.instance.logEvent(
          'community_help_sighting_started',
          {'source': 'community_help_detail'},
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This post is no longer active.')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingConversationScreen(
          conversationId: conversationId,
          viewerType: 'customer',
        ),
      ),
    );
  }

  Future<void> _claimMissingPet(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawTitle = data['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty ? 'Missing pet' : rawTitle;
    return AuthRequiredAction.run(
      context,
      action: () async {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ListingClaimRequestScreen(
              listingType: 'community_help_missing_pet',
              listingId: doc.id,
              listingTitle: title,
            ),
          ),
        );
      },
    );
  }

  Future<void> _showReplySheet(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};
    final mode = data['mode'] as String? ?? 'lost';
    final controller = TextEditingController();
    File? sightingImage;
    bool isSending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode == 'found'
                        ? 'Describe why this is yours'
                        : 'Share what you saw',
                    style: const TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mode == 'found'
                        ? 'Keep identifying details private so the poster can check the claim.'
                        : 'Send the poster a private note with the time, place or details.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Write a short private message',
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: isSending
                        ? null
                        : () async {
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 78,
                            );
                            if (picked == null) return;
                            setSheetState(() {
                              sightingImage = File(picked.path);
                            });
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      sightingImage == null
                          ? 'Attach sighting photo optional'
                          : 'Sighting photo attached',
                    ),
                  ),
                  if (sightingImage != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        sightingImage!,
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final message = controller.text.trim();
                        if (message.isEmpty && sightingImage == null) return;
                        final navigator = Navigator.of(sheetContext);
                        setSheetState(() => isSending = true);
                        final user = FirebaseAuth.instance.currentUser;
                        String? sightingPhotoUrl;
                        if (user != null && sightingImage != null) {
                          sightingPhotoUrl = await _uploadSightingImage(
                            user.uid,
                            sightingImage!,
                          );
                        }
                        navigator.pop();
                        await _sendPrivateReply(
                          doc,
                          message.isEmpty ? 'I may have seen this.' : message,
                          sightingPhotoUrl,
                        );
                      },
                      icon: const Icon(Icons.lock_outline),
                      label: Text(isSending ? 'Sending...' : 'Send privately'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.buttonText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _publishPublicUpdate(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PublicUpdateDialog(),
    );

    if (text == null || text.isEmpty) return;

    try {
      await BookingMessagingService().publishCommunityHelpUpdate(
        postId: doc.id,
        text: text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update shared with followers.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = communityHelpPublicUpdateFailureMessage(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _shareCommunityHelpPost(
    DocumentSnapshot<Map<String, dynamic>> doc,
    BuildContext shareContext,
  ) async {
    try {
      await CommunityHelpShareService().sharePost(
        postId: doc.id,
        post: doc.data() ?? {},
        sharePositionOrigin: _shareOrigin(shareContext),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing could not be started. Please try again.'),
        ),
      );
    }
  }

  Future<void> _copyCommunityHelpLink(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    try {
      await CommunityHelpShareService.copyPostLink(doc.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link copied')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link could not be copied.')),
      );
    }
  }

  Rect? _shareOrigin(BuildContext shareContext) {
    final renderObject = shareContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  Future<void> _openInitialPost(String postId) async {
    final doc = await FirebaseFirestore.instance
        .collection('communityHelpPosts')
        .doc(postId)
        .get();

    if (!mounted) return;

    if (!doc.exists || doc.data() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Community Help post is no longer available.'),
        ),
      );
      return;
    }

    _openPostDetail(doc);
  }

  void _openPostDetail(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    LocalLinkAnalytics.instance.discoveryView(
      eventName: 'community_help_view',
      source: widget.initialPostId == doc.id ? 'shared_link' : 'browse',
      category: data['category']?.toString() ?? data['type']?.toString() ?? '',
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => _LostFoundDetailSheet(
        post: doc,
        onContact: () => _showReplySheet(doc),
        onResolve: () => _markResolved(doc),
        onRenew: () => _renewPost(doc),
        onShare: (shareContext) => _shareCommunityHelpPost(doc, shareContext),
        onCopyLink: () => _copyCommunityHelpLink(doc),
        onPublishUpdate: () => _publishPublicUpdate(doc),
        onClaimMissingPet: () => _claimMissingPet(doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Community help'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const LocalLinkSectionHeader(
            title: 'Lost & Found',
            subtitle: 'Help neighbours find missing pets and lost property.',
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          _ReportChoicePanel(
            onReportLost: () => _startLostFoundReport('lost'),
            onReportFound: () => _startLostFoundReport('found'),
          ),
          if (helpType != null) ...[
            const SizedBox(height: LocalLinkSpacing.lg),
            _CommunityHelpForm(
              isLostFound: _isLostFound,
              lostFoundMode: lostFoundMode,
              freeItemMode: freeItemMode,
              itemCategory: itemCategory,
              titleController: titleController,
              petTypeController: petTypeController,
              descriptionController: descriptionController,
              locationController: locationController,
              timingController: timingController,
              observedAt: observedAt,
              collectionController: collectionController,
              selectedImage: selectedImage,
              locationSuggestions: locationSuggestions,
              locationResolved:
                  selectedLatitude != null && selectedLongitude != null,
              isLocating: isLocating,
              isSaving: isSaving,
              onLostFoundModeChanged: _setLostFoundMode,
              onFreeItemModeChanged: (value) {
                setState(() => freeItemMode = value);
              },
              onItemCategoryChanged: (value) {
                setState(() {
                  itemCategory = value;
                  if (!_isPetCategory(value)) petTypeController.clear();
                });
              },
              onLocationChanged: _searchLocations,
              onLocationSelected: _selectLocationSuggestion,
              onUseCurrentLocation: _useCurrentLocation,
              onPickObservedAt: _pickObservedAt,
              onPickImage: _pickImage,
              onPublish: _publish,
            ),
          ],
          const SizedBox(height: 28),
          KeyedSubtree(
            key: _nearbySectionKey,
            child: _LostFoundDiscoveryList(onOpenPost: _openPostDetail),
          ),
          const SizedBox(height: 26),
          _FollowingCommunityPostsList(onOpenPost: _openPostDetail),
          const SizedBox(height: 26),
          _MyCommunityPostsList(onOpenPost: _openPostDetail),
        ],
      ),
    );
  }
}

class _ReportChoicePanel extends StatelessWidget {
  const _ReportChoicePanel({
    required this.onReportLost,
    required this.onReportFound,
  });

  final VoidCallback onReportLost;
  final VoidCallback onReportFound;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocalLinkButton(
          label: 'Report something lost',
          icon: Icons.search_outlined,
          onPressed: onReportLost,
          expand: true,
        ),
        const SizedBox(height: LocalLinkSpacing.sm),
        LocalLinkButton(
          label: 'Report something found',
          icon: Icons.inventory_2_outlined,
          onPressed: onReportFound,
          variant: LocalLinkButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class _CommunityHelpForm extends StatelessWidget {
  const _CommunityHelpForm({
    required this.isLostFound,
    required this.lostFoundMode,
    required this.freeItemMode,
    required this.itemCategory,
    required this.titleController,
    required this.petTypeController,
    required this.descriptionController,
    required this.locationController,
    required this.timingController,
    required this.observedAt,
    required this.collectionController,
    required this.selectedImage,
    required this.locationSuggestions,
    required this.locationResolved,
    required this.isLocating,
    required this.isSaving,
    required this.onLostFoundModeChanged,
    required this.onFreeItemModeChanged,
    required this.onItemCategoryChanged,
    required this.onLocationChanged,
    required this.onLocationSelected,
    required this.onUseCurrentLocation,
    required this.onPickObservedAt,
    required this.onPickImage,
    required this.onPublish,
  });

  final bool isLostFound;
  final String lostFoundMode;
  final String freeItemMode;
  final String itemCategory;
  final TextEditingController titleController;
  final TextEditingController petTypeController;
  final TextEditingController descriptionController;
  final TextEditingController locationController;
  final TextEditingController timingController;
  final DateTime? observedAt;
  final TextEditingController collectionController;
  final File? selectedImage;
  final List<AddressResult> locationSuggestions;
  final bool locationResolved;
  final bool isLocating;
  final bool isSaving;
  final ValueChanged<String> onLostFoundModeChanged;
  final ValueChanged<String> onFreeItemModeChanged;
  final ValueChanged<String> onItemCategoryChanged;
  final ValueChanged<String> onLocationChanged;
  final ValueChanged<AddressResult> onLocationSelected;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onPickObservedAt;
  final VoidCallback onPickImage;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final isFound = isLostFound && lostFoundMode == 'found';
    final isPet = isLostFound && _isPetCategory(itemCategory);
    final titleLabel = isFound
        ? (isPet ? 'Pet name or short description' : 'What did you find?')
        : isPet
        ? 'Pet name'
        : isLostFound
        ? 'What have you lost?'
        : 'Item';
    final titleHint = isFound
        ? (isPet ? 'Unknown cat, friendly dog...' : 'Keys, phone, bag...')
        : isPet
        ? 'Woody'
        : isLostFound
        ? 'House keys, phone, bag...'
        : 'Moving boxes, children\'s bike, garden chairs...';
    final descriptionHint = isFound
        ? 'Describe the item without sharing every identifying detail.'
        : isPet
        ? 'Type, colour, markings, collar or anything people should look for.'
        : isLostFound
        ? 'Add identifying info or anything people should look for.'
        : 'Describe condition, size and anything helpful.';
    final locationLabel = isFound
        ? 'Where did you find it?'
        : isLostFound
        ? 'Where was it last seen?'
        : 'Approximate collection area';
    final timingLabel = isFound
        ? 'When did you find it?'
        : isLostFound
        ? 'When was it last seen?'
        : 'When is it available or needed? optional';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuestionLabel(isLostFound ? 'Lost or found?' : 'Wanted or offering?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: isLostFound
              ? [
                  _ModeChip(
                    label: 'Lost',
                    selected: lostFoundMode == 'lost',
                    onSelected: () => onLostFoundModeChanged('lost'),
                  ),
                  _ModeChip(
                    label: 'Found',
                    selected: lostFoundMode == 'found',
                    onSelected: () => onLostFoundModeChanged('found'),
                  ),
                ]
              : [
                  _ModeChip(
                    label: 'Wanted',
                    selected: freeItemMode == 'wanted',
                    onSelected: () => onFreeItemModeChanged('wanted'),
                  ),
                  _ModeChip(
                    label: 'Offering',
                    selected: freeItemMode == 'offering',
                    onSelected: () => onFreeItemModeChanged('offering'),
                  ),
                ],
        ),
        if (isLostFound) ...[
          const SizedBox(height: 18),
          const _QuestionLabel('Item type'),
          DropdownButtonFormField<String>(
            initialValue: itemCategory,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: _lostFoundCategories
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onItemCategoryChanged(value);
            },
          ),
          if (isPet) ...[
            const SizedBox(height: 18),
            const _QuestionLabel('Pet type'),
            TextField(
              controller: petTypeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Dog, cat, rabbit...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
        const SizedBox(height: 18),
        _QuestionLabel(titleLabel),
        TextField(
          controller: titleController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: titleHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        const _QuestionLabel('Description'),
        TextField(
          controller: descriptionController,
          minLines: 4,
          maxLines: 7,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: descriptionHint,
            border: const OutlineInputBorder(),
          ),
        ),
        if (isFound) ...[
          const SizedBox(height: 10),
          const _FoundSafetyNotice(),
        ],
        const SizedBox(height: 18),
        _QuestionLabel(locationLabel),
        const _LocationPrivacyCopy(),
        TextField(
          controller: locationController,
          onChanged: onLocationChanged,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Search area or landmark',
            border: OutlineInputBorder(),
          ),
        ),
        if (locationSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _LocationSuggestions(
            suggestions: locationSuggestions,
            onSelected: onLocationSelected,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: isLocating ? null : onUseCurrentLocation,
              icon: isLocating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_outlined, size: 18),
              label: Text(
                isLocating ? 'Locating...' : 'Use my current location',
              ),
            ),
            const SizedBox(width: 8),
            if (locationResolved)
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 20,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _QuestionLabel(timingLabel),
        if (isLostFound)
          _ObservedAtPicker(
            value: observedAt,
            mode: lostFoundMode,
            onTap: onPickObservedAt,
          )
        else
          TextField(
            controller: timingController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Today, yesterday evening, this weekend...',
              border: OutlineInputBorder(),
            ),
          ),
        if (!isLostFound) ...[
          const SizedBox(height: 18),
          const _QuestionLabel('Collection / delivery'),
          TextField(
            controller: collectionController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'Collection only, can drop locally, needs collecting...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Free items only. No prices, deposits, bidding or paid work.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 18),
        _ImagePickerField(selectedImage: selectedImage, onTap: onPickImage),
        if (isFound) ...[
          const SizedBox(height: 8),
          const Text(
            'Do not upload photos showing bank cards, passports, driving licences, IDs or private information.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 22),
        LocalLinkButton(
          label: isSaving ? 'Sharing...' : 'Share with the community',
          icon: Icons.send_outlined,
          isLoading: isSaving,
          expand: true,
          onPressed: isSaving ? null : onPublish,
        ),
      ],
    );
  }
}

class _LocationPrivacyCopy extends StatelessWidget {
  const _LocationPrivacyCopy();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        'Use an approximate public area, not a full address or precise home location.',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

class _LocationSuggestions extends StatelessWidget {
  const _LocationSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  final List<AddressResult> suggestions;
  final ValueChanged<AddressResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: suggestions.map((suggestion) {
          final isLast = suggestion == suggestions.last;
          return Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.place_outlined,
                  color: AppColors.primary,
                ),
                title: Text(
                  suggestion.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () => onSelected(suggestion),
              ),
              if (!isLast) const Divider(height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _FoundSafetyNotice extends StatelessWidget {
  const _FoundSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: const Text(
        'Don\'t show every identifying detail. Leave something for the owner to describe when claiming the item.',
        style: TextStyle(
          color: AppColors.charcoal,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }
}

class _ObservedAtPicker extends StatelessWidget {
  const _ObservedAtPicker({
    required this.value,
    required this.mode,
    required this.onTap,
  });

  final DateTime? value;
  final String mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? (mode == 'found'
              ? 'Choose date and time found'
              : 'Choose date and time last seen')
        : CommunityHelpLifecycle.observedAtText({
            'observedAt': value,
          }, DateTime.now());

    return LocalLinkSurfaceCard(
      onTap: onTap,
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        children: [
          const LocalLinkIconBadge(
            icon: Icons.schedule_outlined,
            color: AppColors.communityTeal,
            size: 40,
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: LocalLinkTextStyles.bodyStrong),
                const SizedBox(height: LocalLinkSpacing.xxs),
                const Text(
                  'This keeps the alert accurate as time passes.',
                  style: LocalLinkTextStyles.metadata,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.charcoal,
        fontWeight: FontWeight.w900,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({required this.selectedImage, required this.onTap});

  final File? selectedImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: onTap,
      elevated: false,
      padding: EdgeInsets.zero,
      radius: LocalLinkRadius.md,
      child: SizedBox(
        height: selectedImage == null ? 112 : 204,
        width: double.infinity,
        child: selectedImage == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LocalLinkIconBadge(
                    icon: Icons.add_photo_alternate_outlined,
                    color: AppColors.communityTeal,
                  ),
                  SizedBox(height: LocalLinkSpacing.sm),
                  Text(
                    'Add a helpful photo',
                    style: LocalLinkTextStyles.bodyStrong,
                  ),
                  SizedBox(height: LocalLinkSpacing.xxs),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: LocalLinkSpacing.md,
                    ),
                    child: Text(
                      'Optional, but especially useful for missing pets.',
                      textAlign: TextAlign.center,
                      style: LocalLinkTextStyles.metadata,
                    ),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                child: Image.file(selectedImage!, fit: BoxFit.cover),
              ),
      ),
    );
  }
}

class _LostFoundDiscoveryList extends StatefulWidget {
  const _LostFoundDiscoveryList({required this.onOpenPost});

  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onOpenPost;

  @override
  State<_LostFoundDiscoveryList> createState() =>
      _LostFoundDiscoveryListState();
}

class _LostFoundDiscoveryListState extends State<_LostFoundDiscoveryList> {
  Position? _userPosition;
  bool _locationLookupComplete = false;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final position = await LocationService().getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _userPosition = position;
      _locationLookupComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_locationLookupComplete) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: LocalLinkSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userPosition == null) {
      return const _EmptyCommunityHelpState(
        icon: Icons.location_on_outlined,
        title: 'Set your location to see missing pets near you',
        message:
            'LocalLink only shows missing pets and lost property when it can check they are nearby.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('communityHelpPosts')
          .where('type', isEqualTo: 'lost_found')
          .where('isActive', isEqualTo: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final docs = (snapshot.data?.docs.toList() ?? []).where((doc) {
          final data = doc.data();
          return CommunityHelpLifecycle.isActiveForDiscovery(data, now) &&
              LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
                data,
                userLatitude: _userPosition?.latitude,
                userLongitude: _userPosition?.longitude,
              );
        }).toList();
        docs.sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aPet =
              aData['itemCategory'] == CommunityHelpLifecycle.petCategory;
          final bPet =
              bData['itemCategory'] == CommunityHelpLifecycle.petCategory;
          if (aPet != bPet) return aPet ? -1 : 1;

          final aCreated = CommunityHelpLifecycle.asDateTime(
            aData['createdAt'],
          );
          final bCreated = CommunityHelpLifecycle.asDateTime(
            bData['createdAt'],
          );
          if (aCreated != null && bCreated != null) {
            return bCreated.compareTo(aCreated);
          }
          return 0;
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nearby',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (docs.isEmpty)
              const Text(
                'No active lost or found reports nearby right now.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              ...docs
                  .take(12)
                  .map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LostFoundCard(
                        post: doc,
                        onTap: () => widget.onOpenPost(doc),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _FollowingCommunityPostsList extends StatelessWidget {
  const _FollowingCommunityPostsList({required this.onOpenPost});

  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const SizedBox.shrink();

    return StreamBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
      stream: CommunityHelpFollowingService().watchFollowing(user.uid),
      builder: (context, snapshot) {
        final docs = snapshot.data?.toList() ?? [];
        docs.sort((a, b) {
          final aUpdated = CommunityHelpLifecycle.asDateTime(
            a.data()?['updatedAt'] ?? a.data()?['createdAt'],
          );
          final bUpdated = CommunityHelpLifecycle.asDateTime(
            b.data()?['updatedAt'] ?? b.data()?['createdAt'],
          );
          if (aUpdated != null && bUpdated != null) {
            return bUpdated.compareTo(aUpdated);
          }
          return 0;
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Following',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Reports you're actively keeping a lookout for.",
              style: LocalLinkTextStyles.metadata,
            ),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.hasError)
              const Text(
                "We couldn't load the reports you're following.",
                style: LocalLinkTextStyles.metadata,
              )
            else if (docs.isEmpty)
              const Text(
                'Tap “Keep a lookout” on a report to follow its updates.',
                style: LocalLinkTextStyles.metadata,
              )
            else
              ...docs
                  .take(12)
                  .map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LostFoundCard(
                        post: doc,
                        onTap: () => onOpenPost(doc),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _EmptyCommunityHelpState extends StatelessWidget {
  const _EmptyCommunityHelpState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.lg),
      child: LocalLinkSurfaceCard(
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: LocalLinkSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyCommunityPostsList extends StatelessWidget {
  const _MyCommunityPostsList({required this.onOpenPost});

  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return CommunityHelpOwnReports(
      userId: user == null || user.isAnonymous ? null : user.uid,
      reportBuilder: (doc) => _LostFoundCard(
        post: doc,
        onTap: () => onOpenPost(doc),
      ),
    );
  }
}

class _LostFoundCard extends StatelessWidget {
  const _LostFoundCard({required this.post, required this.onTap});

  final DocumentSnapshot<Map<String, dynamic>> post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = post.data() ?? {};
    final mode = data['mode'] as String? ?? 'lost';
    final type = data['type'] as String? ?? 'lost_found';
    final isLost = mode == 'lost';
    final title = data['title'] as String? ?? 'Untitled';
    final location = CommunityHelpLocation.publicLabel(data);
    final category = data['itemCategory'] as String? ?? 'Item';
    final itemLabel = data['petType'] as String? ?? category;
    final timing = CommunityHelpLifecycle.observedAtText(data, DateTime.now());
    final photoUrl = data['photoUrl'] as String?;
    final lookoutCount = (data['lookoutCount'] as num?)?.toInt() ?? 0;
    final status = CommunityHelpLifecycle.friendlyStatus(data, DateTime.now());
    final isResolved = CommunityHelpLifecycle.isResolved(data);
    final isPet = _isPetCategory(category);
    final isMissingPet = isLost && isPet;
    final accent = _communityAccent(mode: mode, type: type);
    final statusLabel = status == 'Expired' || isResolved
        ? status.toUpperCase()
        : type == 'free_item'
        ? status.toUpperCase()
        : isLost
        ? 'MISSING'
        : 'FOUND';

    if (isMissingPet) {
      return LocalLinkSurfaceCard(
        onTap: onTap,
        elevated: false,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PostHeroImage(
              photoUrl: photoUrl,
              mode: mode,
              type: type,
              category: category,
              aspectRatio: 16 / 10,
            ),
            Padding(
              padding: const EdgeInsets.all(LocalLinkSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: LocalLinkSpacing.xs,
                    runSpacing: LocalLinkSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusPill(label: statusLabel),
                      Text(itemLabel, style: LocalLinkTextStyles.metadata),
                      if (status == 'Expired' && statusLabel != 'EXPIRED')
                        const _StatusPill(label: 'EXPIRED'),
                    ],
                  ),
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.sectionTitle,
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xs),
                    _DetailLine(
                      icon: Icons.place_outlined,
                      label: 'Last seen near',
                      value: location,
                      accent: accent,
                    ),
                  ],
                  if (timing.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xs),
                    _DetailLine(
                      icon: Icons.schedule_outlined,
                      label: 'Time last seen',
                      value: timing,
                      accent: accent,
                    ),
                  ],
                  if (lookoutCount > 0) ...[
                    const SizedBox(height: LocalLinkSpacing.sm),
                    Text(
                      '$lookoutCount people keeping a lookout',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LocalLinkTextStyles.label.copyWith(
                        color: AppColors.serviceGreen,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LocalLinkSurfaceCard(
      onTap: onTap,
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.sm),
      child: Row(
        children: [
          _PostThumb(
            photoUrl: photoUrl,
            mode: mode,
            type: type,
            category: category,
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusPill(label: statusLabel),
                    Text(itemLabel, style: LocalLinkTextStyles.metadata),
                    if (status == 'Expired' && statusLabel != 'EXPIRED')
                      const _StatusPill(label: 'EXPIRED'),
                  ],
                ),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.cardTitle,
                ),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(
                  [
                    location,
                    timing,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.metadata,
                ),
                if (isLost && lookoutCount > 0) ...[
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    '$lookoutCount people keeping a lookout',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.label.copyWith(
                      color: AppColors.serviceGreen,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _LostFoundDetailSheet extends StatelessWidget {
  const _LostFoundDetailSheet({
    required this.post,
    required this.onContact,
    required this.onResolve,
    required this.onRenew,
    required this.onShare,
    required this.onCopyLink,
    required this.onPublishUpdate,
    required this.onClaimMissingPet,
  });

  final DocumentSnapshot<Map<String, dynamic>> post;
  final VoidCallback onContact;
  final VoidCallback onResolve;
  final VoidCallback onRenew;
  final ValueChanged<BuildContext> onShare;
  final VoidCallback onCopyLink;
  final VoidCallback onPublishUpdate;
  final VoidCallback onClaimMissingPet;

  @override
  Widget build(BuildContext context) {
    final data = post.data() ?? {};
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final ownerId = resolveCommunityHelpOwnerId(data);
    final isOwner = ownerId != null && ownerId == userId;
    final mode = data['mode'] as String? ?? 'lost';
    final type = data['type'] as String? ?? 'lost_found';
    final isLost = mode == 'lost';
    final title = data['title'] as String? ?? 'Untitled';
    final description = data['description'] as String? ?? '';
    final location = CommunityHelpLocation.publicLabel(data);
    final category = data['itemCategory'] as String? ?? 'Item';
    final itemLabel = data['petType'] as String? ?? category;
    final photoUrl = data['photoUrl'] as String?;
    final lookoutCount = (data['lookoutCount'] as num?)?.toInt() ?? 0;
    final isPet = _isPetCategory(category);
    final isCommunityAddedPet = isCommunityAddedMissingPet(data);
    final isClaimableCommunityAddedPet = canClaimCommunityAddedMissingPet(data);
    final claimStatus = data['claimStatus']?.toString() ?? '';
    final now = DateTime.now();
    final timing = CommunityHelpLifecycle.observedAtText(data, now);
    final isExpired = CommunityHelpLifecycle.isExpired(data, now);
    final isResolved = CommunityHelpLifecycle.isResolved(data);
    final isActive = CommunityHelpLifecycle.isActiveForDiscovery(data, now);
    final friendlyStatus = CommunityHelpLifecycle.friendlyStatus(data, now);
    final resolveLabel = CommunityHelpLifecycle.resolveActionLabel(
      type: type,
      mode: mode,
      itemCategory: category,
    );
    final responseLabel = CommunityHelpLifecycle.responseActionLabel(data);
    final accent = _communityAccent(mode: mode, type: type);
    final statusLabel = type == 'free_item'
        ? friendlyStatus.toUpperCase()
        : isExpired || isResolved
        ? friendlyStatus.toUpperCase()
        : isLost
        ? 'MISSING'
        : 'FOUND';
    final shareLabel = isResolved
        ? isLost && isPet
              ? 'Share reunited update'
              : 'Share resolved update'
        : 'Share alert';
    final locationLabel = isLost
        ? 'Last seen near'
        : type == 'free_item'
        ? 'Area'
        : 'Found near';
    final timingLabel = isLost
        ? 'Time last seen'
        : type == 'free_item'
        ? 'Timing'
        : 'Time found';
    final shouldShowDescription =
        description.trim().isNotEmpty &&
        description.trim().toLowerCase() != title.trim().toLowerCase() &&
        description.trim().toLowerCase() != category.trim().toLowerCase();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _PostHeroImage(
              photoUrl: photoUrl,
              mode: mode,
              type: type,
              category: category,
              aspectRatio: isPet ? 4 / 3 : 16 / 10,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: LocalLinkSpacing.xs,
              runSpacing: LocalLinkSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusPill(label: statusLabel),
                if (isCommunityAddedPet)
                  const _StatusPill(label: 'COMMUNITY-ADDED'),
                Text(friendlyStatus, style: LocalLinkTextStyles.metadata),
              ],
            ),
            if (isCommunityAddedPet) ...[
              const SizedBox(height: 12),
              _LifecycleMessage(
                icon: Icons.verified_user_outlined,
                text: claimStatus == 'pending'
                    ? 'Ownership claim pending. A LocalLink moderator will review it.'
                    : ownerId == null
                    ? 'Community-added missing pet. This post was added by LocalLink from community information.'
                    : 'This missing pet post has been claimed by the owner.',
              ),
            ],
            const SizedBox(height: 10),
            Text(
              title,
              style: LocalLinkTextStyles.screenTitle.copyWith(fontSize: 26),
            ),
            const SizedBox(height: LocalLinkSpacing.sm),
            LocalLinkSurfaceCard(
              elevated: false,
              color: AppColors.elevatedSurface,
              padding: const EdgeInsets.all(LocalLinkSpacing.md),
              child: Column(
                children: [
                  _DetailLine(
                    icon: isPet
                        ? Icons.pets_outlined
                        : Icons.inventory_2_outlined,
                    label: type == 'free_item'
                        ? 'Post type'
                        : 'What to look for',
                    value: itemLabel,
                    accent: accent,
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.sm),
                    _DetailLine(
                      icon: Icons.place_outlined,
                      label: locationLabel,
                      value: location,
                      accent: accent,
                    ),
                  ],
                  if (timing.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.sm),
                    _DetailLine(
                      icon: Icons.schedule_outlined,
                      label: timingLabel,
                      value: timing,
                      accent: accent,
                    ),
                  ],
                ],
              ),
            ),
            if (isLost && lookoutCount > 0) ...[
              const SizedBox(height: 12),
              _LifecycleMessage(
                icon: Icons.visibility_outlined,
                text:
                    '$lookoutCount ${lookoutCount == 1 ? 'person is' : 'people are'} keeping a lookout.',
              ),
            ],
            if (!isLost && category != 'Pet') ...[
              const SizedBox(height: 12),
              const _LifecycleMessage(
                icon: Icons.privacy_tip_outlined,
                text:
                    'Keep one identifying detail private so the owner can describe it when claiming the item.',
              ),
            ],
            if (shouldShowDescription) ...[
              const SizedBox(height: 18),
              const _QuestionLabel('Description'),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 22),
            if (isOwner) ...[
              if (isExpired)
                LocalLinkButton(
                  label: 'Keep this active',
                  icon: Icons.refresh_outlined,
                  onPressed: onRenew,
                  expand: true,
                ),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LocalLinkButton(
                    label: 'Post an update',
                    icon: Icons.campaign_outlined,
                    onPressed: onPublishUpdate,
                    variant: LocalLinkButtonVariant.secondary,
                    expand: true,
                  ),
                ),
              if (isActive)
                LocalLinkButton(
                  label: resolveLabel,
                  icon: Icons.check_circle_outline,
                  onPressed: onResolve,
                  variant: LocalLinkButtonVariant.primary,
                  expand: true,
                ),
              if (isResolved)
                const _LifecycleMessage(
                  icon: Icons.check_circle_outline,
                  text: 'This post is resolved and kept in your history.',
                ),
            ] else if (isActive)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isClaimableCommunityAddedPet)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LocalLinkButton(
                        label: 'Is this your pet? Claim this post',
                        icon: Icons.verified_user_outlined,
                        onPressed: onClaimMissingPet,
                        expand: true,
                      ),
                    ),
                  if (ownerId != null)
                    LocalLinkButton(
                      label: isLost && isPet
                          ? 'I may have seen this pet'
                          : responseLabel,
                      icon: Icons.lock_outline,
                      onPressed: onContact,
                      expand: true,
                    )
                  else if (isCommunityAddedPet)
                    const _LifecycleMessage(
                      icon: Icons.privacy_tip_outlined,
                      text:
                          'Private sightings will open once the owner has claimed this post.',
                    ),
                  if (isLost) ...[
                    const SizedBox(height: LocalLinkSpacing.sm),
                    _FollowUpdatesButton(postId: post.id),
                  ],
                ],
              )
            else
              const _LifecycleMessage(
                icon: Icons.info_outline,
                text: 'This post is no longer active.',
              ),
            const SizedBox(height: 10),
            LocalLinkButton(
              label: shareLabel,
              icon: Icons.ios_share_outlined,
              onPressed: () => onShare(context),
              variant: LocalLinkButtonVariant.secondary,
              expand: true,
            ),
            const SizedBox(height: 10),
            LocalLinkButton(
              label: 'Copy link',
              icon: Icons.link_outlined,
              onPressed: onCopyLink,
              variant: LocalLinkButtonVariant.secondary,
              expand: true,
            ),
            const SizedBox(height: 22),
            _PublicUpdatesList(postId: post.id),
            const SizedBox(height: 8),
            if (isActive) _PossibleMatches(currentPost: post),
          ],
        );
      },
    );
  }
}

class _LifecycleMessage extends StatelessWidget {
  const _LifecycleMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      color: AppColors.elevatedSurface,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(child: Text(text, style: LocalLinkTextStyles.metadata)),
        ],
      ),
    );
  }
}

// Classify the existing callable failure without changing retry or cooldown policy.
String communityHelpPublicUpdateFailureMessage(Object error) {
  return error is FirebaseFunctionsException && error.code == 'resource-exhausted'
      ? 'Updates can be sent every 30 minutes.'
      : "We couldn't share your update. Please try again.";
}

class _PublicUpdateDialog extends StatefulWidget {
  const _PublicUpdateDialog();

  @override
  State<_PublicUpdateDialog> createState() => _PublicUpdateDialogState();
}

class _PublicUpdateDialogState extends State<_PublicUpdateDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share an update'),
      content: TextField(
        controller: _controller,
        maxLength: 240,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Short public update for people keeping a lookout',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Post update'),
        ),
      ],
    );
  }
}

class _ClosingUpdateDialog extends StatefulWidget {
  const _ClosingUpdateDialog({required this.title});

  final String title;

  @override
  State<_ClosingUpdateDialog> createState() => _ClosingUpdateDialogState();
}

class _ClosingUpdateDialogState extends State<_ClosingUpdateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLength: 160,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Optional update for people keeping a lookout',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: LocalLinkSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: LocalLinkTextStyles.status.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: LocalLinkSpacing.xxs),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LocalLinkTextStyles.bodyStrong,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostHeroImage extends StatelessWidget {
  const _PostHeroImage({
    required this.photoUrl,
    required this.mode,
    required this.type,
    required this.category,
    required this.aspectRatio,
  });

  final String? photoUrl;
  final String mode;
  final String type;
  final String category;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return LocalLinkImage(
      imageUrl: photoUrl,
      aspectRatio: aspectRatio,
      fallbackIcon: _communityFallbackIcon(
        mode: mode,
        type: type,
        category: category,
      ),
      accentColor: _communityAccent(mode: mode, type: type),
      semanticLabel: _isPetCategory(category)
          ? 'Community Help pet photo'
          : 'Community Help image',
    );
  }
}

class _FollowUpdatesButton extends StatefulWidget {
  const _FollowUpdatesButton({required this.postId});

  final String postId;

  @override
  State<_FollowUpdatesButton> createState() => _FollowUpdatesButtonState();
}

class _FollowUpdatesButtonState extends State<_FollowUpdatesButton> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();

    final followerRef = FirebaseFirestore.instance
        .collection('communityHelpPosts')
        .doc(widget.postId)
        .collection('followers')
        .doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: followerRef.snapshots(),
      builder: (context, snapshot) {
        final isFollowing = snapshot.data?.exists == true;

        return LocalLinkButton(
          label: _isSaving
              ? 'Saving...'
              : isFollowing
              ? "You're keeping a lookout"
              : 'Keep a lookout',
          icon: isFollowing
              ? Icons.notifications_active_outlined
              : Icons.notifications_none_outlined,
          variant: LocalLinkButtonVariant.secondary,
          expand: true,
          onPressed: _isSaving
              ? null
              : () async {
                  setState(() => _isSaving = true);
                  try {
                    final service = BookingMessagingService();
                    if (isFollowing) {
                      await service.unfollowCommunityHelpPost(widget.postId);
                    } else {
                      await service.followCommunityHelpPost(widget.postId);
                      await LocalLinkAnalytics.instance.logEvent(
                        'community_help_followed',
                        {'source': 'community_help_detail'},
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
        );
      },
    );
  }
}

class _PublicUpdatesList extends StatelessWidget {
  const _PublicUpdatesList({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('communityHelpPosts')
          .doc(postId)
          .collection('updates')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalLinkSectionHeader(title: 'Updates'),
            ...docs.map((doc) {
              final data = doc.data();
              final text = data['text'] as String? ?? '';
              if (text.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
                child: LocalLinkSurfaceCard(
                  elevated: false,
                  color: AppColors.elevatedSurface,
                  padding: const EdgeInsets.all(LocalLinkSpacing.md),
                  child: Text(text, style: LocalLinkTextStyles.body),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _PossibleMatches extends StatelessWidget {
  const _PossibleMatches({required this.currentPost});

  final DocumentSnapshot<Map<String, dynamic>> currentPost;

  @override
  Widget build(BuildContext context) {
    final current = currentPost.data() ?? {};

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('communityHelpPosts')
          .where('type', isEqualTo: 'lost_found')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final now = DateTime.now();
        final matches = snapshot.data!.docs
            .where((doc) {
              if (doc.id == currentPost.id) return false;
              final candidate = doc.data();
              return CommunityHelpLifecycle.shouldMatch(
                current,
                candidate,
                now,
              );
            })
            .take(3)
            .toList();

        if (matches.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalLinkSectionHeader(title: 'Possible matches'),
            ...matches.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CompactMatchCard(post: match),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CompactMatchCard extends StatelessWidget {
  const _CompactMatchCard({required this.post});

  final QueryDocumentSnapshot<Map<String, dynamic>> post;

  @override
  Widget build(BuildContext context) {
    final data = post.data();
    final mode = data['mode'] as String? ?? 'lost';
    final title = data['title'] as String? ?? 'Untitled';
    final location = CommunityHelpLocation.publicLabel(data);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _StatusPill(label: mode == 'lost' ? 'LOST' : 'FOUND'),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [title, location].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostThumb extends StatelessWidget {
  const _PostThumb({
    required this.photoUrl,
    required this.mode,
    required this.type,
    required this.category,
  });

  final String? photoUrl;
  final String mode;
  final String type;
  final String category;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 58,
      child: LocalLinkImage(
        imageUrl: photoUrl,
        aspectRatio: 1,
        fallbackIcon: _communityFallbackIcon(
          mode: mode,
          type: type,
          category: category,
        ),
        accentColor: _communityAccent(mode: mode, type: type),
        semanticLabel: _isPetCategory(category)
            ? 'Community Help pet thumbnail'
            : 'Community Help thumbnail',
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'MISSING' || 'LOST' => AppColors.lost,
      'FOUND' ||
      'AVAILABLE' ||
      'REUNITED' ||
      'RETURNED' ||
      'COLLECTED' ||
      'RESOLVED' => AppColors.success,
      'NO LONGER NEEDED' => AppColors.textMuted,
      'EXPIRED' => AppColors.textMuted,
      _ => AppColors.communityTeal,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LocalLinkRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: LocalLinkTextStyles.status.copyWith(color: color),
      ),
    );
  }
}

class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.charcoal,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }
}
