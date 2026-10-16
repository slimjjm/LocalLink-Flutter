import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/activity_categories.dart';
import '../constants/business_categories.dart';
import '../models/address_result.dart';
import '../models/business_opening_hours.dart';
import '../models/organisation.dart';
import '../services/admin_access_service.dart';
import '../services/populate_area_save_errors.dart';
import '../services/moderator_public_listing_fields.dart';
import '../services/organisation_discovery_service.dart';
import '../services/address_search_service.dart';
import '../services/community_help_lifecycle.dart';
import '../services/local_link_share_service.dart';
import '../services/organisation_service.dart';
import '../theme/app_colors.dart';
import '../widgets/business_opening_hours_editor.dart';
import 'business_detail_screen.dart';
import 'business_profile_screen.dart';
import 'organisation_detail_screen.dart';
import 'opportunity_detail_screen.dart';
import 'post_service_request_screen.dart';

class ModeratorPopulateAreaScreen extends StatefulWidget {
  const ModeratorPopulateAreaScreen({super.key});

  @override
  State<ModeratorPopulateAreaScreen> createState() =>
      _ModeratorPopulateAreaScreenState();
}

class _ModeratorPopulateAreaScreenState
    extends State<ModeratorPopulateAreaScreen> {
  final _db = FirebaseFirestore.instance;
  final _addressService = AddressSearchService();
  final _picker = ImagePicker();

  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _subcategoryController = TextEditingController();
  final _petTypeController = TextEditingController();
  final _ageGroupController = TextEditingController();
  final _sourceUrlController = TextEditingController();
  final _sourceNameController = TextEditingController();
  final _notesController = TextEditingController();

  String _listingType = 'business';
  String _area = 'Burntwood';
  String _listingFilter = 'all';
  String _repeatType = 'none';
  String? _selectedBusinessCategory;
  Organisation? _selectedOrganisation;
  double _serviceRadiusMiles = 5;
  Map<String, dynamic> _openingHours = BusinessOpeningHours.defaultStructured();
  DateTime? _eventDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  double? _latitude;
  double? _longitude;
  XFile? _image;
  List<AddressResult> _suggestions = const [];
  bool _saving = false;

  static const _areas = [
    'Burntwood',
    'Lichfield',
    'Tamworth',
    'Shrewsbury',
    'Other',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _subcategoryController.dispose();
    _petTypeController.dispose();
    _ageGroupController.dispose();
    _sourceUrlController.dispose();
    _sourceNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _searchPlaces(String query) async {
    _latitude = null;
    _longitude = null;
    if (query.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }

    final results = await _addressService.search(query);
    if (!mounted) return;
    setState(() => _suggestions = results);
  }

  Future<void> _selectPlace(AddressResult result) async {
    final coords = await _addressService.getCoordinates(result.placeId);
    if (!mounted) return;
    setState(() {
      _locationController.text = result.description;
      _latitude = coords?['lat'];
      _longitude = coords?['lng'];
      _suggestions = const [];
    });
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
    );
    if (image == null || !mounted) return;
    setState(() => _image = image);
  }

  Future<bool> _confirmLikelyDuplicate({
    required String title,
    required String location,
    DateTime? eventDate,
  }) async {
    final collection = _collectionForListingType(_listingType);
    final snapshot = await _db
        .collection(collection)
        .where('isActive', isEqualTo: true)
        .limit(80)
        .get();

    final matches = <_DuplicateCandidate>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final existingTitle = _titleForDuplicate(data);
      final existingLocation =
          (data['address'] ?? data['location'] ?? data['publicLocation'] ?? '')
              .toString();

      final nameSimilar = _looksSimilar(title, existingTitle);
      final locationSimilar =
          _looksSimilar(location, existingLocation) ||
          _looksSimilar(_area, data['area']?.toString() ?? '');
      final geographicallyNear = _isNear(data);
      final nearInTime =
          _listingType == 'business' ||
          _isNearEventTime(eventDate, data['eventDate']);

      if (nameSimilar &&
          (locationSimilar || geographicallyNear) &&
          nearInTime) {
        matches.add(
          _DuplicateCandidate(
            title: existingTitle.isEmpty ? doc.id : existingTitle,
            detail: existingLocation.isEmpty
                ? (_listingType == 'business' ? 'Business' : 'Event')
                : existingLocation,
          ),
        );
      }
    }

    if (matches.isEmpty) return true;
    if (!mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Possible duplicate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LocalLink found similar listings nearby. Check these before adding another one.',
              ),
              const SizedBox(height: 12),
              ...matches
                  .take(4)
                  .map(
                    (match) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('- ${match.title}\n${match.detail}'),
                    ),
                  ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue anyway'),
            ),
          ],
        );
      },
    );

    return proceed == true;
  }

  String _collectionForListingType(String listingType) {
    if (listingType == 'business') return 'businesses';
    if (listingType == 'organisation') return 'organisations';
    if (listingType == 'community_missing_pet') return 'communityHelpPosts';
    return 'opportunities';
  }

  String _titleForDuplicate(Map<String, dynamic> data) {
    if (_listingType == 'business') {
      return data['businessName']?.toString() ?? '';
    }
    if (_listingType == 'organisation') {
      return data['name']?.toString() ?? '';
    }
    return data['title']?.toString() ?? '';
  }

  bool _looksSimilar(String a, String b) {
    final left = _normaliseForMatch(a);
    final right = _normaliseForMatch(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    if (left.length >= 5 && right.contains(left)) return true;
    if (right.length >= 5 && left.contains(right)) return true;

    final leftWords = left.split(' ').where((word) => word.length > 2).toSet();
    final rightWords = right
        .split(' ')
        .where((word) => word.length > 2)
        .toSet();
    if (leftWords.isEmpty || rightWords.isEmpty) return false;
    final overlap = leftWords.intersection(rightWords).length;
    return overlap >=
        math.min(2, math.min(leftWords.length, rightWords.length));
  }

  String _normaliseForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isNear(Map<String, dynamic> data) {
    if (_latitude == null || _longitude == null) return false;
    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');
    if (lat == null || lng == null) return false;
    return _milesBetween(_latitude!, _longitude!, lat, lng) <= 0.35;
  }

  double _milesBetween(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMiles = 3958.8;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMiles * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  bool _isNearEventTime(DateTime? newDate, Object? existingDate) {
    if (newDate == null || existingDate is! Timestamp) return true;
    final days = existingDate.toDate().difference(newDate).inDays.abs();
    return days <= 1;
  }

  Future<String?> _uploadImage({
    required String listingId,
    required String moderatorId,
  }) async {
    final image = _image;
    if (image == null) return null;

    final bytes = await image.readAsBytes();
    if (bytes.length >= populateAreaImageSizeLimit) {
      throw const FormatException('Choose an image smaller than 8 MB.');
    }
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final folder = _listingType == 'business'
        ? 'businessPhotos/$listingId'
        : _listingType == 'community_missing_pet'
        ? 'communityHelpPhotos/$moderatorId'
        : 'opportunityPhotos/$moderatorId';
    final path = '$folder/$fileName';
    final metadata = {
      'ownerId': moderatorId,
      'moderatorSeeded': 'true',
      'listingId': listingId,
    };
    if (kDebugMode) {
      final user = FirebaseAuth.instance.currentUser;
      final appBelievesAdmin = await AdminAccessService().isCurrentUserAdmin();
      final adminDebug = await _debugAdminAccessSnapshot(user);
      debugPrint(
        'Populate Area image upload: '
        'uid=${user?.uid}, '
        'path=$path, '
        'contentType=image/jpeg, '
        'metadata=$metadata, '
        'appBelievesAdmin=$appBelievesAdmin, '
        '$adminDebug',
      );
    }
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg', customMetadata: metadata),
    );
    return ref.getDownloadURL();
  }

  Future<String> _debugAdminAccessSnapshot(User? user) async {
    if (user == null) return 'adminDebug=no-user';

    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final hasAdminProfileFlag = AdminAccessService.hasAdminProfileFlag(
        userData,
      );
      final email = user.email?.trim().toLowerCase();
      var adminEmailDocExists = false;
      Object? adminEmailEnabled;
      Object? adminEmailLookupError;
      if (email != null && email.isNotEmpty) {
        try {
          final adminEmailDoc = await _db
              .collection('adminEmails')
              .doc(email)
              .get();
          adminEmailDocExists = adminEmailDoc.exists;
          adminEmailEnabled = adminEmailDoc.data()?['enabled'];
        } catch (error) {
          adminEmailLookupError = error.runtimeType;
        }
      }

      return 'adminDebug='
          'userDocExists=${userDoc.exists}, '
          'userIsAdmin=$hasAdminProfileFlag, '
          'adminEmailDocExists=$adminEmailDocExists, '
          'adminEmailEnabled=$adminEmailEnabled, '
          'adminEmailLookupError=$adminEmailLookupError';
    } catch (error) {
      return 'adminDebug=unavailable(${error.runtimeType})';
    }
  }

  Future<void> _saveListing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in before adding a listing.')),
      );
      return;
    }

    final title = _titleController.text.trim();
    final isCommunityMissingPet = _listingType == 'community_missing_pet';
    final category = isCommunityMissingPet
        ? CommunityHelpLifecycle.petCategory
        : _listingType == 'business'
        ? _selectedBusinessCategory?.trim() ?? ''
        : ActivityCategories.normalise(_categoryController.text);
    final location = _locationController.text.trim();
    final petType = _petTypeController.text.trim();
    final eventTimeLabel = _startTime?.format(context) ?? '';
    final endTimeLabel = _endTime?.format(context) ?? '';

    final businessValidation = _listingType == 'business'
        ? populateAreaBusinessValidation(
            title: title,
            category: category,
            location: location,
            latitude: _latitude,
            longitude: _longitude,
            radius: _serviceRadiusMiles,
          )
        : null;
    if (businessValidation != null ||
        title.isEmpty ||
        category.isEmpty ||
        location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            businessValidation ?? 'Add a name, category and location.',
          ),
        ),
      );
      return;
    }

    if (isCommunityMissingPet && petType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add the pet type, such as dog or cat.')),
      );
      return;
    }

    var stage = PopulateAreaSaveStage.authorization;
    var listingSaved = false;
    try {
      setState(() => _saving = true);
      if (!await AdminAccessService().isCurrentUserAdmin()) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      }
      stage = PopulateAreaSaveStage.duplicateCheck;

      final shouldContinue = await _confirmLikelyDuplicate(
        title: title,
        location: location,
        eventDate: _eventDate,
      );
      if (!shouldContinue) {
        return;
      }

      // Public Populate Area activities must use a current public organisation.
      stage = PopulateAreaSaveStage.authorization;
      final selectedOrganisation = _selectedOrganisation;
      if (selectedOrganisation != null &&
          !const [
            'business',
            'organisation',
            'community_missing_pet',
          ].contains(_listingType)) {
        final parent = await _db
            .collection('organisations')
            .doc(selectedOrganisation.id)
            .get();
        if (!parent.exists ||
            !OrganisationDiscoveryService.isDiscoverable(parent.data() ?? {})) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Choose an active public organisation. Use the activity audience controls for restricted content.',
              ),
            ),
          );
          return;
        }
      }

      final collection = _db.collection(
        _collectionForListingType(_listingType),
      );
      final ref = collection.doc();
      stage = PopulateAreaSaveStage.imageUpload;
      final imageUrl = await _uploadImage(
        listingId: ref.id,
        moderatorId: user.uid,
      );

      stage = PopulateAreaSaveStage.listingSave;
      final businessBatch = _listingType == 'business' ? _db.batch() : null;
      final base = <String, dynamic>{
        'createdByModerator': true,
        'listingOwnershipStatus': 'unclaimed',
        'claimedByUserId': null,
        'claimedAt': null,
        'claimStatus': 'unclaimed',
        'area': _area,
        'publicLocation': _area == 'Other' ? location : _area,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      Map<String, dynamic>? createdBusinessData;
      if (_listingType == 'business') {
        createdBusinessData = {
          ...base,
          'businessName': title,
          'name': title,
          'category': category,
          'description': _descriptionController.text.trim(),
          'bio': _descriptionController.text.trim(),
          'address': location,
          'latitude': _latitude,
          'longitude': _longitude,
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'website': _websiteController.text.trim(),
          'openingHoursStructured': _openingHours,
          'openingHours': BusinessOpeningHours.summary(_openingHours),
          'serviceRadiusMiles': _serviceRadiusMiles,
          'serviceMode': 'premises',
          'createdBy': user.uid,
          'ownerId': '',
          'businessOwnerId': '',
          'isClaimed': false,
          'isActive': true,
          'acceptingLeads': false,
          'paymentMethods': const ['cash'],
          'stripeRequested': false,
          'stripeConnected': false,
          'stripeChargesEnabled': false,
          'schedulingMode': 'simple',
          if (imageUrl != null) 'photoURLs': [imageUrl],
        };
        businessBatch!.set(ref, createdBusinessData);
      } else if (_listingType == 'organisation') {
        final subcategories = _normalisedCsv(_subcategoryController.text);
        await ref.set({
          ...base,
          ...ModeratorPublicListingFields.organisation,
          'name': title,
          'description': _descriptionController.text.trim(),
          'category': category,
          'subcategories': subcategories,
          'location': location,
          'address': location,
          'latitude': _latitude,
          'longitude': _longitude,
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'website': _websiteController.text.trim(),
          'ownerId': '',
          'adminUserIds': const [],
          'createdBy': user.uid,
          'isActive': true,
          'imageUrl': imageUrl,
        });
      } else if (isCommunityMissingPet) {
        final now = DateTime.now();
        final observedAt = _eventDate == null
            ? null
            : CommunityHelpLifecycle.normaliseObservedAt(
                DateTime(
                  _eventDate!.year,
                  _eventDate!.month,
                  _eventDate!.day,
                  _startTime?.hour ?? 0,
                  _startTime?.minute ?? 0,
                ),
                now,
              );
        final observedDateOnly = _eventDate != null && _startTime == null;
        final timingText = observedAt == null
            ? 'Reported missing'
            : CommunityHelpLifecycle.observedAtText({
                'observedAt': observedAt,
                if (observedDateOnly) 'observedDateOnly': true,
              }, now);
        final expiresAt = CommunityHelpLifecycle.expiresAt(
          now: now,
          type: 'lost_found',
          mode: CommunityHelpLifecycle.lostMode,
          itemCategory: CommunityHelpLifecycle.petCategory,
        );
        await ref.set({
          ...base,
          'createdBy': user.uid,
          'createdByName': 'LocalLink',
          'createdByModerator': true,
          'communityAdded': true,
          'ownerId': null,
          'claimStatus': 'unclaimed',
          'claimedBy': null,
          'claimedAt': null,
          'claimReviewedBy': null,
          'claimReviewedAt': null,
          'type': 'lost_found',
          'mode': CommunityHelpLifecycle.lostMode,
          'title': title,
          'description': _descriptionController.text.trim(),
          'location': location,
          'publicLocation': location,
          'locationPrecision': 'approximate',
          'locationSource': _latitude != null && _longitude != null
              ? 'place_search'
              : 'manual',
          'approxLatitude': _latitude,
          'approxLongitude': _longitude,
          'discoveryRadiusMiles':
              CommunityHelpLifecycle.defaultDiscoveryRadiusMiles(
                type: 'lost_found',
                mode: CommunityHelpLifecycle.lostMode,
                itemCategory: CommunityHelpLifecycle.petCategory,
              ),
          'timing': timingText,
          'eventDateText': timingText,
          if (observedDateOnly) 'observedDateOnly': true,
          if (observedAt != null) 'observedAt': Timestamp.fromDate(observedAt),
          if (observedAt != null) 'lastSeenAt': Timestamp.fromDate(observedAt),
          'itemCategory': CommunityHelpLifecycle.petCategory,
          'petType': petType,
          'keywords': CommunityHelpLifecycle.keywordsFor(
            '$title $petType ${_descriptionController.text} $location $_area',
          ),
          'collectionDetails': '',
          'photoUrl': imageUrl ?? '',
          'isFree': false,
          'allowsPayment': false,
          'status': CommunityHelpLifecycle.activeStatus,
          'lifecycleKind': CommunityHelpLifecycle.lifecycleKind(
            type: 'lost_found',
            mode: CommunityHelpLifecycle.lostMode,
            itemCategory: CommunityHelpLifecycle.petCategory,
          ),
          'renewalCount': 0,
          'expiryReminderAt': Timestamp.fromDate(
            CommunityHelpLifecycle.expiryReminderAt(expiresAt),
          ),
          'expiryReminderStatus': 'pending',
          'isActive': true,
          'expiresAt': Timestamp.fromDate(expiresAt),
        });
      } else {
        final linkedOrganisation = selectedOrganisation;
        final activitySubcategories = _normalisedCsv(
          _subcategoryController.text,
        );
        final opportunityData = {
          ...base,
          'title': title,
          'category': category,
          'description': _descriptionController.text.trim(),
          'location': location,
          'latitude': _latitude,
          'longitude': _longitude,
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'website': _websiteController.text.trim(),
          'organiserName': linkedOrganisation?.name ?? 'Unclaimed organiser',
          'createdBy': user.uid,
          'organiserId': null,
          if (activitySubcategories.isNotEmpty)
            'activityType': activitySubcategories.first,
          ...ModeratorPublicListingFields.activity(
            organisation: linkedOrganisation,
          ),
          if (_ageGroupController.text.trim().isNotEmpty)
            'ageGroup': _ageGroupController.text.trim(),
          if (_scheduleText().isNotEmpty) 'scheduleText': _scheduleText(),
          'attendeeCount': 0,
          'eventDate': _eventDate == null
              ? null
              : Timestamp.fromDate(_eventDate!),
          'eventTime': eventTimeLabel,
          'endTime': endTimeLabel,
          'isActive': true,
          'isRecurring': _repeatType != 'none',
          if (_repeatType != 'none') 'recurrenceTimeZone': 'Europe/London',
          'repeatType': _repeatType,
          'seriesId': ref.id,
          'seriesStatus': 'active',
          'reminder24hSent': false,
          'reminder1hSent': false,
        };
        if (imageUrl != null) {
          opportunityData['photoUrl'] = imageUrl;
        }
        await ref.set(opportunityData);
        if (linkedOrganisation != null) {
          await _db.collection('organisations').doc(linkedOrganisation.id).set({
            'activityCount': FieldValue.increment(1),
            'subcategories': FieldValue.arrayUnion(activitySubcategories),
            'updatedAt': FieldValue.serverTimestamp(),
            if (_eventDate != null) ...{
              'latestAddedSessionAt': Timestamp.fromDate(_eventDate!),
              'latestAddedSessionTitle': title,
            },
          }, SetOptions(merge: true));
        }
      }

      final metadataRef = _db
          .collection('moderatorListingMetadata')
          .doc(ref.id);
      final metadata = <String, dynamic>{
        'listingType': _listingType,
        'listingId': ref.id,
        'sourceUrl': _sourceUrlController.text.trim(),
        'sourceName': _sourceNameController.text.trim(),
        'moderatorNotes': _notesController.text.trim(),
        'seededByModeratorUserId': user.uid,
        'area': _area,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (businessBatch != null) {
        businessBatch.set(metadataRef, metadata);
        await businessBatch.commit();
      } else {
        await metadataRef.set(metadata);
      }

      listingSaved = true;
      if (!mounted) return;
      final createdOrganisation = _listingType == 'organisation'
          ? Organisation(
              id: ref.id,
              name: title,
              description: _descriptionController.text.trim(),
              category: category,
              subcategories: _normalisedCsv(_subcategoryController.text),
              area: _area,
              publicLocation: _area == 'Other' ? location : _area,
              location: location,
              phone: _phoneController.text.trim(),
              email: _emailController.text.trim(),
              website: _websiteController.text.trim(),
              imageUrl: imageUrl ?? '',
              ownerId: '',
              adminUserIds: const [],
              createdByModerator: true,
              claimStatus: 'unclaimed',
              listingOwnershipStatus: 'unclaimed',
              isActive: true,
              capabilities: OrganisationCapabilities.defaultsFor(
                category: category,
                subcategories: _normalisedCsv(_subcategoryController.text),
                name: title,
              ),
              latitude: _latitude,
              longitude: _longitude,
            )
          : null;
      _clearForm();
      if (createdOrganisation != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Organisation added.'),
            action: SnackBarAction(
              label: 'Add Activity',
              onPressed: () =>
                  _startActivityForOrganisation(createdOrganisation),
            ),
          ),
        );
      } else if (_listingType == 'business' && createdBusinessData != null) {
        await _showBusinessAddedDialog(
          businessId: ref.id,
          businessData: createdBusinessData,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_listingTypeLabel()} added.')),
        );
      }
    } catch (error, stackTrace) {
      // Release diagnostics deliberately omit form values, URLs and personal data.
      final code = error is FirebaseException
          ? error.code
          : error.runtimeType.toString();
      debugPrint('Populate Area save failed: stage=${stage.name}, code=$code');
      if (kDebugMode) debugPrint('$stackTrace');
      if (!mounted) return;
      final message = listingSaved
          ? 'The listing was saved, but the confirmation could not be opened. Check existing listings before adding it again.'
          : error is FormatException &&
                stage == PopulateAreaSaveStage.imageUpload
          ? error.message
          : populateAreaSaveError(error, stage);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showBusinessAddedDialog({
    required String businessId,
    required Map<String, dynamic> businessData,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Business added'),
          content: Text(
            '${businessData['businessName'] ?? businessData['name'] ?? 'The business'} is now saved. You can open the listing directly or share its public LocalLink page.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await LocalLinkShareService().shareItem(
                  item: LocalLinkShareItem(
                    type: LocalLinkShareItemType.business,
                    id: businessId,
                    data: businessData,
                  ),
                );
              },
              child: const Text('Share with business'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BusinessDetailScreen(businessId: businessId),
                  ),
                );
              },
              child: const Text('View listing'),
            ),
          ],
        );
      },
    );
  }

  void _clearForm() {
    _titleController.clear();
    _categoryController.clear();
    _descriptionController.clear();
    _locationController.clear();
    _phoneController.clear();
    _emailController.clear();
    _websiteController.clear();
    _subcategoryController.clear();
    _petTypeController.clear();
    _ageGroupController.clear();
    _selectedBusinessCategory = null;
    _selectedOrganisation = null;
    _repeatType = 'none';
    _openingHours = BusinessOpeningHours.defaultStructured();
    _sourceUrlController.clear();
    _sourceNameController.clear();
    _notesController.clear();
    _eventDate = null;
    _startTime = null;
    _endTime = null;
    _latitude = null;
    _longitude = null;
    _image = null;
    _suggestions = const [];
  }

  String _listingTypeLabel() {
    if (_listingType == 'business') return 'Business';
    if (_listingType == 'organisation') return 'Organisation';
    if (_listingType == 'community_missing_pet') return 'Missing pet';
    return 'Event';
  }

  List<String> _normalisedCsv(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _scheduleText() {
    final parts = [
      if (_eventDate != null)
        '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}',
      if (_startTime != null) _startTime!.format(context),
      if (_endTime != null) '- ${_endTime!.format(context)}',
    ];
    return parts.join(' ');
  }

  void _startActivityForOrganisation(Organisation organisation) {
    setState(() {
      _listingType = 'opportunity';
      _selectedOrganisation = organisation;
      _categoryController.text = organisation.category;
      _subcategoryController.text = organisation.subcategories.join(', ');
      _petTypeController.clear();
      _locationController.text = organisation.location;
      _latitude = organisation.latitude;
      _longitude = organisation.longitude;
      _area = organisation.area.isEmpty ? _area : organisation.area;
      _image = null;
      _eventDate = null;
      _startTime = null;
      _endTime = null;
      _repeatType = 'none';
    });
  }

  void _selectOrganisationForActivity(Organisation? organisation) {
    setState(() {
      _selectedOrganisation = organisation;
      if (organisation == null) return;

      _categoryController.text = organisation.category;
      _subcategoryController.text = organisation.subcategories.join(', ');
      _locationController.text = organisation.location;
      _latitude = organisation.latitude;
      _longitude = organisation.longitude;
    });
  }

  Future<void> _openListing(String type, String id) async {
    if (id.isEmpty) return;
    if (type == 'business') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BusinessDetailScreen(businessId: id)),
      );
      return;
    }

    if (type == 'organisation') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrganisationDetailScreen(organisationId: id),
        ),
      );
      return;
    }

    if (type == 'community_help_missing_pet') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostServiceRequestScreen(initialPostId: id),
        ),
      );
      return;
    }

    final doc = await _db.collection('opportunities').doc(id).get();
    if (!mounted || !doc.exists || doc.data() == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunityId: id,
          opportunity: doc.data()!,
        ),
      ),
    );
  }

  Future<void> _editBusiness(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BusinessProfileScreen(businessId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Populate Area'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SeedListingForm(
            listingType: _listingType,
            area: _area,
            titleController: _titleController,
            categoryController: _categoryController,
            selectedBusinessCategory: _selectedBusinessCategory,
            selectedOrganisation: _selectedOrganisation,
            descriptionController: _descriptionController,
            locationController: _locationController,
            phoneController: _phoneController,
            emailController: _emailController,
            websiteController: _websiteController,
            subcategoryController: _subcategoryController,
            petTypeController: _petTypeController,
            ageGroupController: _ageGroupController,
            openingHours: _openingHours,
            sourceUrlController: _sourceUrlController,
            sourceNameController: _sourceNameController,
            notesController: _notesController,
            suggestions: _suggestions,
            eventDate: _eventDate,
            startTime: _startTime,
            endTime: _endTime,
            repeatType: _repeatType,
            serviceRadiusMiles: _serviceRadiusMiles,
            hasImage: _image != null,
            saving: _saving,
            onListingTypeChanged: (value) =>
                setState(() => _listingType = value),
            onBusinessCategoryChanged: (value) =>
                setState(() => _selectedBusinessCategory = value),
            onOrganisationChanged: _selectOrganisationForActivity,
            onOpeningHoursChanged: (value) =>
                setState(() => _openingHours = value),
            onLocationChanged: _searchPlaces,
            onSuggestionSelected: _selectPlace,
            onPickImage: _pickImage,
            onSave: _saveListing,
            onRadiusChanged: (value) =>
                setState(() => _serviceRadiusMiles = value),
            onPickDate: () async {
              final now = DateTime.now();
              final isMissingPetDate = _listingType == 'community_missing_pet';
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _eventDate ??
                    (isMissingPetDate
                        ? CommunityHelpLifecycle.latestSelectableObservedAt(now)
                        : now),
                firstDate: isMissingPetDate
                    ? CommunityHelpLifecycle.firstSelectableObservedDate(now)
                    : now,
                lastDate: isMissingPetDate
                    ? CommunityHelpLifecycle.latestSelectableObservedAt(now)
                    : DateTime(2035),
              );
              if (picked != null && mounted) {
                setState(() => _eventDate = picked);
              }
            },
            onPickStartTime: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _startTime ?? TimeOfDay.now(),
              );
              if (picked != null && mounted) {
                setState(() => _startTime = picked);
              }
            },
            onPickEndTime: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _endTime ?? TimeOfDay.now(),
              );
              if (picked != null && mounted) {
                setState(() => _endTime = picked);
              }
            },
            onRepeatTypeChanged: (value) => setState(() => _repeatType = value),
          ),
          const SizedBox(height: 16),
          _SeededListingsSection(
            db: _db,
            area: _area,
            areas: _areas,
            filter: _listingFilter,
            onAreaChanged: (area) => setState(() => _area = area),
            onFilterChanged: (value) => setState(() => _listingFilter = value),
            onOpenListing: _openListing,
            onAddActivity: _startActivityForOrganisation,
            onEditBusiness: _editBusiness,
          ),
        ],
      ),
    );
  }
}

class _SeedListingForm extends StatelessWidget {
  const _SeedListingForm({
    required this.listingType,
    required this.area,
    required this.titleController,
    required this.categoryController,
    required this.selectedBusinessCategory,
    required this.selectedOrganisation,
    required this.descriptionController,
    required this.locationController,
    required this.phoneController,
    required this.emailController,
    required this.websiteController,
    required this.subcategoryController,
    required this.petTypeController,
    required this.ageGroupController,
    required this.openingHours,
    required this.sourceUrlController,
    required this.sourceNameController,
    required this.notesController,
    required this.suggestions,
    required this.eventDate,
    required this.startTime,
    required this.endTime,
    required this.repeatType,
    required this.serviceRadiusMiles,
    required this.hasImage,
    required this.saving,
    required this.onListingTypeChanged,
    required this.onBusinessCategoryChanged,
    required this.onOrganisationChanged,
    required this.onOpeningHoursChanged,
    required this.onLocationChanged,
    required this.onSuggestionSelected,
    required this.onPickImage,
    required this.onSave,
    required this.onRadiusChanged,
    required this.onPickDate,
    required this.onPickStartTime,
    required this.onPickEndTime,
    required this.onRepeatTypeChanged,
  });

  final String listingType;
  final String area;
  final TextEditingController titleController;
  final TextEditingController categoryController;
  final String? selectedBusinessCategory;
  final Organisation? selectedOrganisation;
  final TextEditingController descriptionController;
  final TextEditingController locationController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController websiteController;
  final TextEditingController subcategoryController;
  final TextEditingController petTypeController;
  final TextEditingController ageGroupController;
  final Map<String, dynamic> openingHours;
  final TextEditingController sourceUrlController;
  final TextEditingController sourceNameController;
  final TextEditingController notesController;
  final List<AddressResult> suggestions;
  final DateTime? eventDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String repeatType;
  final double serviceRadiusMiles;
  final bool hasImage;
  final bool saving;
  final ValueChanged<String> onListingTypeChanged;
  final ValueChanged<String?> onBusinessCategoryChanged;
  final ValueChanged<Organisation?> onOrganisationChanged;
  final ValueChanged<Map<String, dynamic>> onOpeningHoursChanged;
  final ValueChanged<String> onLocationChanged;
  final ValueChanged<AddressResult> onSuggestionSelected;
  final VoidCallback onPickImage;
  final VoidCallback onSave;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickStartTime;
  final VoidCallback onPickEndTime;
  final ValueChanged<String> onRepeatTypeChanged;

  @override
  Widget build(BuildContext context) {
    final isBusiness = listingType == 'business';
    final isOrganisation = listingType == 'organisation';
    final isEvent = listingType == 'opportunity';
    final isCommunityMissingPet = listingType == 'community_missing_pet';

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add listing',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'business', label: Text('Business')),
                ButtonSegment(
                  value: 'organisation',
                  label: Text('Organisation'),
                ),
                ButtonSegment(
                  value: 'opportunity',
                  label: Text('Standalone Event'),
                ),
                ButtonSegment(
                  value: 'community_missing_pet',
                  label: Text('Missing pet'),
                ),
              ],
              selected: {listingType},
              onSelectionChanged: (values) =>
                  onListingTypeChanged(values.first),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: isBusiness
                  ? 'Business name'
                  : isOrganisation
                  ? 'Organisation name'
                  : isCommunityMissingPet
                  ? 'Pet name or short alert'
                  : 'Event name',
            ),
          ),
          const SizedBox(height: 10),
          if (isBusiness)
            DropdownButtonFormField<String>(
              initialValue: selectedBusinessCategory,
              decoration: const InputDecoration(labelText: 'Business category'),
              items: BusinessCategories.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: onBusinessCategoryChanged,
            )
          else if (!isCommunityMissingPet)
            DropdownButtonFormField<String>(
              key: ValueKey('event-category-${categoryController.text}'),
              initialValue:
                  ActivityCategories.values.contains(
                    ActivityCategories.normalise(categoryController.text),
                  )
                  ? ActivityCategories.normalise(categoryController.text)
                  : null,
              decoration: const InputDecoration(labelText: 'Event category'),
              items: ActivityCategories.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                categoryController.text = value ?? '';
              },
            ),
          if (isCommunityMissingPet) ...[
            TextField(
              controller: petTypeController,
              decoration: const InputDecoration(
                labelText: 'Pet type',
                hintText: 'Dog, cat, rabbit...',
              ),
            ),
          ],
          if (isOrganisation || isEvent) ...[
            const SizedBox(height: 10),
            TextField(
              controller: subcategoryController,
              decoration: InputDecoration(
                labelText: isOrganisation
                    ? 'Subcategories'
                    : 'Activity type / subcategory',
                hintText: 'Rugby, Hockey, Toddler group',
              ),
            ),
          ],
          if (isEvent) ...[
            const SizedBox(height: 10),
            StreamBuilder<List<Organisation>>(
              stream: OrganisationService().watchModeratorSeededOrganisations(
                area: area,
              ),
              builder: (context, snapshot) {
                final organisations = snapshot.data ?? const [];
                final selectedOrganisationId =
                    organisations.any(
                      (organisation) =>
                          organisation.id == selectedOrganisation?.id,
                    )
                    ? selectedOrganisation?.id
                    : '';
                return DropdownButtonFormField<String>(
                  initialValue: selectedOrganisationId,
                  decoration: const InputDecoration(
                    labelText: 'Parent organisation',
                    helperText:
                        'Optional. Linked activities remain normal events.',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No parent organisation'),
                    ),
                    ...organisations.map(
                      (organisation) => DropdownMenuItem(
                        value: organisation.id,
                        child: Text(organisation.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null || value.isEmpty) {
                      onOrganisationChanged(null);
                      return;
                    }

                    Organisation? selected;
                    for (final organisation in organisations) {
                      if (organisation.id == value) {
                        selected = organisation;
                        break;
                      }
                    }
                    onOrganisationChanged(selected);
                  },
                );
              },
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: descriptionController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Original description',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: locationController,
            decoration: InputDecoration(
              labelText: isBusiness || isOrganisation
                  ? 'Address/place'
                  : isCommunityMissingPet
                  ? 'Last seen area'
                  : 'Venue/location',
              helperText: 'Approximate public area: $area',
            ),
            onChanged: onLocationChanged,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...suggestions
                .take(5)
                .map(
                  (item) => ListTile(
                    dense: true,
                    title: Text(item.description),
                    onTap: () => onSuggestionSelected(item),
                  ),
                ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SmallField(controller: phoneController, label: 'Public phone'),
              _SmallField(controller: emailController, label: 'Public email'),
              _SmallField(controller: websiteController, label: 'Website'),
            ],
          ),
          if (isBusiness) ...[
            const SizedBox(height: 10),
            BusinessOpeningHoursEditor(
              initialHours: openingHours,
              onChanged: onOpeningHoursChanged,
            ),
            const SizedBox(height: 8),
            Text('Service radius: ${serviceRadiusMiles.toStringAsFixed(0)} mi'),
            Slider(
              min: 1,
              max: 30,
              divisions: 29,
              value: serviceRadiusMiles,
              onChanged: onRadiusChanged,
            ),
          ] else if (isEvent || isCommunityMissingPet) ...[
            const SizedBox(height: 10),
            if (isEvent)
              TextField(
                controller: ageGroupController,
                decoration: const InputDecoration(
                  labelText: 'Age group',
                  hintText: 'Under 8, Adults, Toddlers',
                ),
              ),
            if (isEvent) const SizedBox(height: 10),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    eventDate == null
                        ? isCommunityMissingPet
                              ? 'Last seen date'
                              : 'Date'
                        : '${eventDate!.day}/${eventDate!.month}/${eventDate!.year}',
                  ),
                ),
                if (isEvent) ...[
                  OutlinedButton.icon(
                    onPressed: onPickStartTime,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(
                      startTime == null ? 'Start' : startTime!.format(context),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPickEndTime,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(
                      endTime == null ? 'End' : endTime!.format(context),
                    ),
                  ),
                ],
              ],
            ),
            if (isEvent) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    'none',
                    'daily',
                    'weekly',
                    'fortnightly',
                    'monthly',
                  ])
                    ChoiceChip(
                      label: Text(_repeatLabel(option)),
                      selected: repeatType == option,
                      onSelected: (_) => onRepeatTypeChanged(option),
                    ),
                ],
              ),
            ],
          ],
          const Divider(height: 28),
          TextField(
            controller: sourceNameController,
            decoration: const InputDecoration(labelText: 'Source name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: sourceUrlController,
            decoration: const InputDecoration(labelText: 'Source URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: notesController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Moderator notes'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPickImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(hasImage ? 'Image selected' : 'Add image/logo'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_location_alt_outlined),
              label: Text(
                'Add ${isBusiness
                    ? 'business'
                    : isOrganisation
                    ? 'organisation'
                    : isCommunityMissingPet
                    ? 'missing pet'
                    : 'event'}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _repeatLabel(String value) {
    switch (value) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'fortnightly':
        return 'Fortnightly';
      case 'monthly':
        return 'Monthly';
      default:
        return 'No repeat';
    }
  }
}

class _SeededListingsSection extends StatelessWidget {
  const _SeededListingsSection({
    required this.db,
    required this.area,
    required this.areas,
    required this.filter,
    required this.onAreaChanged,
    required this.onFilterChanged,
    required this.onOpenListing,
    required this.onAddActivity,
    required this.onEditBusiness,
  });

  final FirebaseFirestore db;
  final String area;
  final List<String> areas;
  final String filter;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function(String type, String id) onOpenListing;
  final ValueChanged<Organisation> onAddActivity;
  final Future<void> Function(String id) onEditBusiness;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Existing listings',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: area,
            decoration: const InputDecoration(labelText: 'Area filter'),
            items: areas
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) {
              if (value != null) onAreaChanged(value);
            },
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'unclaimed', label: Text('Unclaimed')),
                ButtonSegment(
                  value: 'claim_requested',
                  label: Text('Claim requested'),
                ),
                ButtonSegment(value: 'claimed', label: Text('Claimed')),
              ],
              selected: {filter},
              onSelectionChanged: (values) => onFilterChanged(values.first),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
            future: Future.wait([
              db
                  .collection('businesses')
                  .where('createdByModerator', isEqualTo: true)
                  .get(),
              db
                  .collection('opportunities')
                  .where('createdByModerator', isEqualTo: true)
                  .get(),
              db
                  .collection('organisations')
                  .where('createdByModerator', isEqualTo: true)
                  .get(),
              db.collection('listingClaims').get(),
            ]),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Listings could not be loaded.');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final businessDocs = snapshot.data![0].docs.where(
                (doc) => doc.data()['area'] == area,
              );
              final eventDocs = snapshot.data![1].docs.where(
                (doc) => doc.data()['area'] == area,
              );
              final organisationDocs = snapshot.data![2].docs.where(
                (doc) => doc.data()['area'] == area,
              );
              final claimsByListing = <String, List<Map<String, dynamic>>>{};
              for (final claimDoc in snapshot.data![3].docs) {
                final claim = claimDoc.data();
                final key = '${claim['listingType']}:${claim['listingId']}';
                claimsByListing.putIfAbsent(key, () => []).add(claim);
              }

              final items =
                  [
                    ...businessDocs.map(
                      (doc) => _SeededListingItem(
                        type: 'business',
                        id: doc.id,
                        data: doc.data(),
                      ),
                    ),
                    ...eventDocs.map(
                      (doc) => _SeededListingItem(
                        type: 'opportunity',
                        id: doc.id,
                        data: doc.data(),
                      ),
                    ),
                    ...organisationDocs.map(
                      (doc) => _SeededListingItem(
                        type: 'organisation',
                        id: doc.id,
                        data: doc.data(),
                      ),
                    ),
                  ].where((item) {
                    final status = _listingStatusFor(
                      item,
                      claimsByListing['${item.type}:${item.id}'] ?? const [],
                    );
                    return filter == 'all' || status == filter;
                  }).toList();

              if (items.isEmpty) {
                return const Text('No listings found in this area.');
              }

              return Column(
                children: items.map((item) {
                  final title = item.type == 'business'
                      ? item.data['businessName']?.toString() ?? 'Business'
                      : item.type == 'organisation'
                      ? item.data['name']?.toString() ?? 'Organisation'
                      : item.data['title']?.toString() ?? 'Event';
                  final claimed =
                      item.data['listingOwnershipStatus'] == 'claimed';
                  final claims =
                      claimsByListing['${item.type}:${item.id}'] ?? const [];
                  final status = _listingStatusFor(item, claims);
                  final claim = _displayClaimFor(status, claims);

                  return _ListingCard(
                    title: title,
                    subtitle:
                        '${_listingTypeTitle(item.type)} · ${item.data['publicLocation'] ?? area}',
                    status: _statusLabel(status),
                    ownerName: _claimedValue(item.data, claim, 'claimantName'),
                    ownerEmail: _claimedValue(
                      item.data,
                      claim,
                      'claimantEmail',
                    ),
                    claimedAt: item.data['claimedAt'],
                    area: item.data['area']?.toString() ?? area,
                    listingType: _listingTypeTitle(item.type),
                    onOpen: () => onOpenListing(item.type, item.id),
                    onAddActivity: item.type == 'organisation'
                        ? () => onAddActivity(
                            Organisation.fromMap(item.id, item.data),
                          )
                        : null,
                    onEdit: item.type == 'business' && !claimed
                        ? () => onEditBusiness(item.id)
                        : null,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _listingStatusFor(
    _SeededListingItem item,
    List<Map<String, dynamic>> claims,
  ) {
    if (item.data['listingOwnershipStatus'] == 'claimed') return 'claimed';
    final hasPendingClaim = claims.any((claim) => claim['status'] == 'pending');
    if (hasPendingClaim) return 'claim_requested';
    return 'unclaimed';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'claimed':
        return 'CLAIMED';
      case 'claim_requested':
        return 'CLAIM REQUESTED';
      default:
        return 'UNCLAIMED';
    }
  }

  String _listingTypeTitle(String type) {
    if (type == 'business') return 'Business';
    if (type == 'organisation') return 'Organisation';
    return 'Event';
  }

  Map<String, dynamic>? _displayClaimFor(
    String status,
    List<Map<String, dynamic>> claims,
  ) {
    final desired = status == 'claimed' ? 'approved' : 'pending';
    for (final claim in claims) {
      if (claim['status'] == desired) return claim;
    }
    return claims.isEmpty ? null : claims.first;
  }

  String _claimedValue(
    Map<String, dynamic> listing,
    Map<String, dynamic>? claim,
    String key,
  ) {
    final value = claim?[key] ?? listing[key];
    return value?.toString().trim() ?? '';
  }
}

class _SeededListingItem {
  const _SeededListingItem({
    required this.type,
    required this.id,
    required this.data,
  });

  final String type;
  final String id;
  final Map<String, dynamic> data;
}

class _DuplicateCandidate {
  const _DuplicateCandidate({required this.title, required this.detail});

  final String title;
  final String detail;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SmallField extends StatelessWidget {
  const _SmallField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.area,
    required this.listingType,
    required this.onOpen,
    this.ownerName = '',
    this.ownerEmail = '',
    this.claimedAt,
    this.onAddActivity,
    this.onEdit,
  });

  final String title;
  final String subtitle;
  final String status;
  final String area;
  final String listingType;
  final String ownerName;
  final String ownerEmail;
  final Object? claimedAt;
  final VoidCallback onOpen;
  final VoidCallback? onAddActivity;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return _MiniCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _StatusPill(status: status),
                    _StatusPill(status: area),
                    _StatusPill(status: listingType),
                  ],
                ),
                if (ownerName.isNotEmpty ||
                    ownerEmail.isNotEmpty ||
                    claimedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (ownerName.isNotEmpty) ownerName,
                      if (ownerEmail.isNotEmpty) ownerEmail,
                      if (claimedAt is Timestamp)
                        'Claimed ${_formatDate((claimedAt as Timestamp).toDate())}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          if (onAddActivity != null)
            IconButton(
              tooltip: 'Add activity',
              onPressed: onAddActivity,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colour = status == 'CLAIMED'
        ? AppColors.success
        : status == 'CLAIM REQUESTED'
        ? AppColors.activityBlue
        : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: colour,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
