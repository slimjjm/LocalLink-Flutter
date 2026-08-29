import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';

import '../models/address_result.dart';
import '../services/address_search_service.dart';
import '../services/booking_messaging_service.dart';
import '../services/community_help_share_service.dart';
import '../services/community_help_lifecycle.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import 'booking_conversation_screen.dart';
import 'business_list_screen.dart';

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

class PostServiceRequestScreen extends StatefulWidget {
  const PostServiceRequestScreen({super.key, this.initialPostId});

  final String? initialPostId;

  @override
  State<PostServiceRequestScreen> createState() =>
      _PostServiceRequestScreenState();
}

class _PostServiceRequestScreenState extends State<PostServiceRequestScreen> {
  final titleController = TextEditingController();
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
    if (postId == null || postId.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialPost(postId);
    });
  }

  void _selectType(_CommunityHelpType type) {
    setState(() {
      helpType = type;
      titleController.clear();
      descriptionController.clear();
      locationController.clear();
      timingController.clear();
      collectionController.clear();
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
    setState(() {
      lostFoundMode = value;
      titleController.clear();
      descriptionController.clear();
      locationController.clear();
      timingController.clear();
      selectedImage = null;
      locationSuggestions = [];
      selectedLatitude = null;
      selectedLongitude = null;
      selectedPlaceId = null;
      locationSource = 'manual';
    });
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

    setState(() {
      selectedLatitude = _softCoordinate(coords['lat']!);
      selectedLongitude = _softCoordinate(coords['lng']!);
      selectedPlaceId = suggestion.placeId;
      locationSource = 'place_search';
      locationController.text = suggestion.description;
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
    final description = descriptionController.text.trim();
    final location = locationController.text.trim();
    final timing = timingController.text.trim();
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
        'location': location,
        'publicLocation': location,
        'locationPrecision': 'approximate',
        'locationSource': locationSource,
        'placeId': selectedPlaceId,
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
        'itemCategory': category,
        'keywords': CommunityHelpLifecycle.keywordsFor(
          '$title $description $category $location',
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
    return double.parse(value.toStringAsFixed(3));
  }

  Future<String> _publicLabelFor(dynamic position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      for (final place in placemarks) {
        final label =
            [place.name, place.thoroughfare, place.subLocality, place.locality]
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

  void _openFindService() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const BusinessListScreen(useCurrentLocation: true),
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Great news — marked as ${_resolvedToastLabel(reason)}.'),
      ),
    );
  }

  Future<String?> _askForClosingUpdate(String reason) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Mark as ${_resolvedToastLabel(reason)}'),
          content: TextField(
            controller: controller,
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
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
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
    if (data['createdBy'] == user.uid) return;

    late final String conversationId;
    try {
      conversationId = await BookingMessagingService()
          .createCommunityHelpConversation(
            postId: doc.id,
            text: message,
            sightingPhotoUrl: sightingPhotoUrl,
          );
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
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Share an update'),
          content: TextField(
            controller: controller,
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
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Post update'),
            ),
          ],
        );
      },
    );
    controller.dispose();

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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updates can be sent every 30 minutes.')),
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
        onPublishUpdate: () => _publishPublicUpdate(doc),
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
          const Text(
            'Community help',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'For lost/found posts and free neighbour-to-neighbour items only.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _PaidWorkNotice(onFindService: _openFindService),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HelpTypeCard(
                  selected: _isLostFound,
                  icon: Icons.manage_search_outlined,
                  title: 'Lost / Found',
                  subtitle: 'Pets, keys, property or found items.',
                  onTap: () => _selectType(_CommunityHelpType.lostFound),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HelpTypeCard(
                  selected: _isFreeItem,
                  icon: Icons.card_giftcard_outlined,
                  title: 'Free items',
                  subtitle: 'Wanted or offered for free.',
                  onTap: () => _selectType(_CommunityHelpType.freeItem),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (helpType == null)
            const _CommunityPrompt()
          else
            _CommunityHelpForm(
              isLostFound: _isLostFound,
              lostFoundMode: lostFoundMode,
              freeItemMode: freeItemMode,
              itemCategory: itemCategory,
              titleController: titleController,
              descriptionController: descriptionController,
              locationController: locationController,
              timingController: timingController,
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
                setState(() => itemCategory = value);
              },
              onLocationChanged: _searchLocations,
              onLocationSelected: _selectLocationSuggestion,
              onUseCurrentLocation: _useCurrentLocation,
              onPickImage: _pickImage,
              onPublish: _publish,
            ),
          const SizedBox(height: 28),
          _LostFoundDiscoveryList(onOpenPost: _openPostDetail),
          const SizedBox(height: 26),
          _MyCommunityPostsList(onOpenPost: _openPostDetail),
        ],
      ),
    );
  }
}

class _PaidWorkNotice extends StatelessWidget {
  const _PaidWorkNotice({required this.onFindService});

  final VoidCallback onFindService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.serviceGreen.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.serviceGreen.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.design_services_outlined,
            color: AppColors.serviceGreen,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Need paid help, like a cleaner or gardener?',
              style: TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          TextButton(
            onPressed: onFindService,
            child: const Text('Find a service'),
          ),
        ],
      ),
    );
  }
}

class _HelpTypeCard extends StatelessWidget {
  const _HelpTypeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.charcoal;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 136),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.border.withValues(alpha: 0.86),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityPrompt extends StatelessWidget {
  const _CommunityPrompt();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Choose Lost / Found or Free items to continue.',
      style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
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
    required this.descriptionController,
    required this.locationController,
    required this.timingController,
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
    required this.onPickImage,
    required this.onPublish,
  });

  final bool isLostFound;
  final String lostFoundMode;
  final String freeItemMode;
  final String itemCategory;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController locationController;
  final TextEditingController timingController;
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
  final VoidCallback onPickImage;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final isFound = isLostFound && lostFoundMode == 'found';
    final titleLabel = isFound
        ? 'What did you find?'
        : isLostFound
        ? 'What have you lost?'
        : 'Item';
    final titleHint = isFound
        ? 'Keys, glasses, child\'s scooter...'
        : isLostFound
        ? 'Black cat, house keys, child\'s scooter...'
        : 'Moving boxes, children\'s bike, garden chairs...';
    final descriptionHint = isFound
        ? 'Describe the item without sharing every identifying detail.'
        : isLostFound
        ? 'Add identifying info, markings, colour or anything people should look for.'
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isSaving ? null : onPublish,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(isSaving ? 'Sharing...' : 'Share with the community'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.buttonText,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
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
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: selectedImage == null ? 96 : 184,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: selectedImage == null
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'Add photo optional',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(selectedImage!, fit: BoxFit.cover),
                ),
        ),
      ),
    );
  }
}

class _LostFoundDiscoveryList extends StatelessWidget {
  const _LostFoundDiscoveryList({required this.onOpenPost});

  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onOpenPost;

  @override
  Widget build(BuildContext context) {
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
          return CommunityHelpLifecycle.isActiveForDiscovery(doc.data(), now);
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
              'Active Lost & Found nearby',
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
                'No active lost or found posts yet.',
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

class _MyCommunityPostsList extends StatelessWidget {
  const _MyCommunityPostsList({required this.onOpenPost});

  final ValueChanged<DocumentSnapshot<Map<String, dynamic>>> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('communityHelpPosts')
          .where('createdBy', isEqualTo: user.uid)
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs.toList() ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        docs.sort((a, b) {
          final aCreated = CommunityHelpLifecycle.asDateTime(
            a.data()['createdAt'],
          );
          final bCreated = CommunityHelpLifecycle.asDateTime(
            b.data()['createdAt'],
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
              'My Community Posts',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ...docs
                .take(6)
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

class _LostFoundCard extends StatelessWidget {
  const _LostFoundCard({required this.post, required this.onTap});

  final DocumentSnapshot<Map<String, dynamic>> post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = post.data() ?? {};
    final mode = data['mode'] as String? ?? 'lost';
    final isLost = mode == 'lost';
    final title = data['title'] as String? ?? 'Untitled';
    final location =
        data['publicLocation'] as String? ?? data['location'] as String? ?? '';
    final timing =
        data['eventDateText'] as String? ?? data['timing'] as String? ?? '';
    final category = data['itemCategory'] as String? ?? 'Item';
    final photoUrl = data['photoUrl'] as String?;
    final lookoutCount = (data['lookoutCount'] as num?)?.toInt() ?? 0;
    final status = CommunityHelpLifecycle.friendlyStatus(data, DateTime.now());

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _PostThumb(photoUrl: photoUrl, mode: mode),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatusPill(label: isLost ? 'LOST' : 'FOUND'),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            category,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (status == 'Expired') ...[
                          const SizedBox(width: 8),
                          const _StatusPill(label: 'EXPIRED'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        location,
                        timing,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isLost && lookoutCount > 0) ...[
                      const SizedBox(height: 5),
                      Text(
                        '$lookoutCount people keeping a lookout',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.serviceGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
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
    required this.onPublishUpdate,
  });

  final DocumentSnapshot<Map<String, dynamic>> post;
  final VoidCallback onContact;
  final VoidCallback onResolve;
  final VoidCallback onRenew;
  final ValueChanged<BuildContext> onShare;
  final VoidCallback onPublishUpdate;

  @override
  Widget build(BuildContext context) {
    final data = post.data() ?? {};
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = data['createdBy'] == userId;
    final mode = data['mode'] as String? ?? 'lost';
    final type = data['type'] as String? ?? 'lost_found';
    final isLost = mode == 'lost';
    final title = data['title'] as String? ?? 'Untitled';
    final description = data['description'] as String? ?? '';
    final location =
        data['publicLocation'] as String? ?? data['location'] as String? ?? '';
    final timing =
        data['eventDateText'] as String? ?? data['timing'] as String? ?? '';
    final category = data['itemCategory'] as String? ?? 'Item';
    final photoUrl = data['photoUrl'] as String?;
    final lookoutCount = (data['lookoutCount'] as num?)?.toInt() ?? 0;
    final now = DateTime.now();
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
            _PostHeroImage(photoUrl: photoUrl, mode: mode),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatusPill(label: isLost ? 'LOST' : 'FOUND'),
                const SizedBox(width: 8),
                Text(
                  friendlyStatus,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 24,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                category,
                location,
                timing,
              ].where((value) => value.isNotEmpty).join(' · '),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
                height: 1.3,
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
                ElevatedButton.icon(
                  onPressed: onRenew,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Keep this active'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.buttonText,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    onPressed: onPublishUpdate,
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Post an update'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              if (isActive)
                ElevatedButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(resolveLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
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
                  if (isLost) _FollowUpdatesButton(postId: post.id),
                  if (isLost) const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: onContact,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(responseLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.buttonText,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              )
            else
              const _LifecycleMessage(
                icon: Icons.info_outline,
                text: 'This post is no longer active.',
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => onShare(context),
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Share alert'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostHeroImage extends StatelessWidget {
  const _PostHeroImage({required this.photoUrl, required this.mode});

  final String? photoUrl;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final image = photoUrl?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: image != null && image.isNotEmpty
            ? Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _PostHeroPlaceholder(mode: mode);
                },
              )
            : _PostHeroPlaceholder(mode: mode),
      ),
    );
  }
}

class _PostHeroPlaceholder extends StatelessWidget {
  const _PostHeroPlaceholder({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Icon(
        mode == 'lost' ? Icons.search_outlined : Icons.inventory_2_outlined,
        color: AppColors.primary,
        size: 42,
      ),
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

        return OutlinedButton.icon(
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
                    }
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
          icon: Icon(
            isFollowing
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
          ),
          label: Text(
            _isSaving
                ? 'Saving...'
                : isFollowing
                ? 'Following updates'
                : 'Keep a lookout',
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
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
            const _QuestionLabel('Updates'),
            ...docs.map((doc) {
              final data = doc.data();
              final text = data['text'] as String? ?? '';
              if (text.isEmpty) return const SizedBox.shrink();

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
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
            const Text(
              'Possible matches',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
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
    final location =
        data['publicLocation'] as String? ?? data['location'] as String? ?? '';

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
  const _PostThumb({required this.photoUrl, required this.mode});

  final String? photoUrl;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final image = photoUrl;
    if (image != null && image.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(image, width: 58, height: 58, fit: BoxFit.cover),
      );
    }

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        mode == 'lost' ? Icons.search_outlined : Icons.inventory_2_outlined,
        color: AppColors.primary,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isLost = label == 'LOST';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isLost ? AppColors.error : AppColors.serviceGreen).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isLost ? AppColors.error : AppColors.serviceGreen,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
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
