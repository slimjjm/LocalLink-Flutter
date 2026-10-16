import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/address_result.dart';
import '../services/address_search_service.dart';
import '../services/analytics_service.dart';
import '../services/booking_messaging_service.dart';
import '../services/local_link_share_service.dart';
import '../services/service_request_marketplace.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import '../widgets/local_link_image.dart';
import '../widgets/service_request_photos.dart';
import 'booking_conversation_screen.dart';
import 'business_detail_screen.dart';

typedef ServiceRequestPhotoPicker = Future<XFile?> Function();
typedef ServiceRequestPhotoUploader =
    Future<List<String>> Function({
      required String requestId,
      required String userId,
      required List<XFile> photos,
    });
typedef ServiceRequestSelectedPhotoBuilder =
    Widget Function(BuildContext context, XFile photo, int index);

const serviceRequestCategories = [
  'Cleaner',
  'Dog Walker',
  'Hair Salon',
  'Barber',
  'Dog Groomer',
  'Gardener',
  'Nails',
  'Personal Trainer',
  'Mobile Valeting',
  'Massage',
  'Handyman',
  'Specialist Services',
];

class MyServiceRequestsScreen extends StatelessWidget {
  const MyServiceRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My service requests'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerServiceRequestScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('New request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (user == null || user.isAnonymous)
            const _MessageState(
              title: 'Sign in to manage requests',
              message:
                  'Create or sign in to a LocalLink account to see service requests you have posted.',
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .where('customerId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  assert(() {
                    debugPrint(
                      'customer serviceRequests query failed: ${snapshot.error}',
                    );
                    return true;
                  }());
                  return const _MessageState(
                    title: 'Unable to load requests',
                    message: 'Please try again in a moment.',
                  );
                }

                final docs = [...snapshot.data?.docs ?? const []];
                docs.sort((a, b) {
                  final aDate = ServiceRequestMarketplace.asDateTime(
                    a.data()['createdAt'],
                  );
                  final bDate = ServiceRequestMarketplace.asDateTime(
                    b.data()['createdAt'],
                  );
                  if (aDate == null && bDate == null) return 0;
                  if (aDate == null) return 1;
                  if (bDate == null) return -1;
                  return bDate.compareTo(aDate);
                });

                if (docs.isEmpty) {
                  return const _MessageState(
                    title: 'No requests yet',
                    message:
                        'Post a request when you need help from local providers.',
                  );
                }

                return Column(
                  children: docs
                      .map(
                        (doc) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MyServiceRequestCard(
                            requestId: doc.id,
                            data: doc.data(),
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

class _MyServiceRequestCard extends StatelessWidget {
  const _MyServiceRequestCard({required this.requestId, required this.data});

  final String requestId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = safeText(data['title'], 'Service request');
    final category = safeText(data['category'], 'Service');
    final location = ServiceRequestMarketplace.publicLocation(data);
    final createdAt = ServiceRequestMarketplace.asDateTime(data['createdAt']);
    final status = _requestStatusLabel(data, DateTime.now());
    final subtitle = [
      category,
      if (location.isNotEmpty) location,
      if (createdAt != null) 'Posted ${_shortDate(createdAt)}',
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CustomerServiceRequestDetailScreen(requestId: requestId),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(label: status, color: _requestStatusColor(status)),
                _Chip(label: category, color: AppColors.charcoal),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'View/manage',
                  style: TextStyle(
                    color: AppColors.serviceGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.serviceGreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _requestStatusLabel(Map<String, dynamic> data, DateTime now) {
  final status = safeText(data['status'], '').toLowerCase();
  if (status == ServiceRequestMarketplace.statusFilled) return 'Completed';
  if (status == ServiceRequestMarketplace.statusClosed) return 'Closed';
  if (status == ServiceRequestMarketplace.statusExpired) return 'Expired';

  final expiresAt = ServiceRequestMarketplace.asDateTime(data['expiresAt']);
  if (expiresAt != null && !expiresAt.isAfter(now)) return 'Expired';
  if (data['isActive'] == false) return 'Closed';
  return 'Live';
}

Color _requestStatusColor(String status) {
  return switch (status) {
    'Live' => AppColors.serviceGreen,
    'Completed' => AppColors.success,
    'Expired' => AppColors.warning,
    'Closed' => AppColors.textMuted,
    _ => AppColors.charcoal,
  };
}

String _shortDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

Rect? _shareOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;

  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

Future<List<String>> _uploadServiceRequestPhotos({
  required String requestId,
  required String userId,
  required List<XFile> photos,
}) async {
  final urls = <String>[];
  final uploadedRefs = <Reference>[];
  try {
    for (var index = 0; index < photos.length && index < 3; index++) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
      final ref = FirebaseStorage.instance.ref().child(
        'serviceRequests/$requestId/images/$fileName',
      );
      await ref.putFile(
        File(photos[index].path),
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'ownerId': userId, 'requestId': requestId},
        ),
      );
      uploadedRefs.add(ref);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  } catch (_) {
    for (final ref in uploadedRefs) {
      await ref.delete().catchError((_) {});
    }
    rethrow;
  }
}

Future<void> _deleteServiceRequestPhotoUrl(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  try {
    await FirebaseStorage.instance.refFromURL(trimmed).delete();
  } catch (_) {
    // Cleanup is best-effort. The request has already stopped referencing it.
  }
}

class CustomerServiceRequestScreen extends StatefulWidget {
  const CustomerServiceRequestScreen({
    super.key,
    this.photoPicker,
    this.photoUploader,
    this.selectedPhotoBuilder,
  });

  final ServiceRequestPhotoPicker? photoPicker;
  final ServiceRequestPhotoUploader? photoUploader;
  final ServiceRequestSelectedPhotoBuilder? selectedPhotoBuilder;

  @override
  State<CustomerServiceRequestScreen> createState() =>
      _CustomerServiceRequestScreenState();
}

class _CustomerServiceRequestScreenState
    extends State<CustomerServiceRequestScreen> {
  static const _maxPhotos = 3;

  final _titleController = TextEditingController(text: 'Cleaner needed');
  final _descriptionController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _budgetController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressSearch = AddressSearchService();
  final _picker = ImagePicker();

  String _category = 'Cleaner';
  double? _latitude;
  double? _longitude;
  bool _isSaving = false;
  bool _isPickingPhoto = false;
  List<AddressResult> _suggestions = [];
  final List<XFile> _selectedPhotos = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _scheduleController.dispose();
    _budgetController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_selectedPhotos.length >= _maxPhotos) {
      _showSnack('You can add up to $_maxPhotos photos.');
      return;
    }
    if (_isPickingPhoto) return;

    setState(() => _isPickingPhoto = true);
    try {
      final picked =
          widget.photoPicker?.call() ??
          _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 78,
            maxWidth: 1600,
          );
      final photo = await picked;
      if (!mounted || photo == null) return;
      if (_selectedPhotos.length >= _maxPhotos) {
        _showSnack('You can add up to $_maxPhotos photos.');
        return;
      }
      setState(() => _selectedPhotos.add(photo));
    } catch (_) {
      if (!mounted) return;
      _showSnack('We could not add that photo. Please try again.');
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  void _removePhoto(int index) {
    if (index < 0 || index >= _selectedPhotos.length) return;
    setState(() => _selectedPhotos.removeAt(index));
  }

  Future<void> _searchLocation(String query) async {
    _latitude = null;
    _longitude = null;
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    final results = await _addressSearch.search(trimmed);
    if (!mounted) return;
    setState(() => _suggestions = results.take(5).toList());
  }

  Future<void> _selectLocation(AddressResult suggestion) async {
    final coords = await _addressSearch.getCoordinates(suggestion.placeId);
    if (!mounted || coords == null) return;

    setState(() {
      _locationController.text = _publicArea(suggestion.description);
      _latitude = _softCoordinate(coords['lat'] ?? 0);
      _longitude = _softCoordinate(coords['lng'] ?? 0);
      _suggestions = [];
    });
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final schedule = _scheduleController.text.trim();
    final location = _locationController.text.trim();
    if (user == null || user.isAnonymous) {
      _showSnack('Please sign in to post a request.');
      return;
    }
    if (title.isEmpty ||
        description.isEmpty ||
        schedule.isEmpty ||
        location.isEmpty ||
        _latitude == null ||
        _longitude == null) {
      _showSnack('Add what you need, roughly where, and when.');
      return;
    }

    setState(() => _isSaving = true);
    final commands = ServiceRequestCommands();
    final requestRef = commands.requests.doc();
    try {
      final request = await commands.createRequest(
        requestId: requestRef.id,
        customerId: user.uid,
        category: _category,
        title: title,
        description: description,
        scheduleText: schedule,
        publicLocation: location,
        approxLatitude: _latitude!,
        approxLongitude: _longitude!,
        budgetText: _budgetController.text,
      );

      if (_selectedPhotos.isNotEmpty) {
        try {
          final uploader = widget.photoUploader ?? _uploadSelectedPhotos;
          final imageUrls = await uploader(
            requestId: request.id,
            userId: user.uid,
            photos: List<XFile>.unmodifiable(_selectedPhotos),
          );
          await commands.updateRequestImages(
            requestId: request.id,
            imageUrls: imageUrls,
          );
        } catch (_) {
          await commands.deleteRequest(request.id).catchError((_) {});
          rethrow;
        }
      }

      if (!mounted) return;
      _showSnack('Your request is live for local providers.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CustomerServiceRequestDetailScreen(requestId: request.id),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _selectedPhotos.isEmpty
            ? 'We could not post this request. Please try again.'
            : 'We could not upload your photos. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<List<String>> _uploadSelectedPhotos({
    required String requestId,
    required String userId,
    required List<XFile> photos,
  }) => _uploadServiceRequestPhotos(
    requestId: requestId,
    userId: userId,
    photos: photos,
  );

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _softCoordinate(double value) =>
      double.parse(value.toStringAsFixed(3));

  String _publicArea(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return value.trim();
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Request local help'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Tell nearby providers what you need.',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: serviceRequestCategories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What do you need?'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Details',
              hintText: 'Weekly clean, 2-3 hours, kitchen and bathrooms...',
            ),
          ),
          const SizedBox(height: 12),
          _PhotoPickerField(
            photos: _selectedPhotos,
            maxPhotos: _maxPhotos,
            isPicking: _isPickingPhoto,
            onAdd: _pickPhoto,
            onRemove: _removePhoto,
            thumbnailBuilder: widget.selectedPhotoBuilder,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _scheduleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'When?',
              hintText: 'Friday mornings, weekly',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _budgetController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Budget or rate expectation (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            onChanged: _searchLocation,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Approximate area',
              hintText: 'Burntwood',
            ),
          ),
          if (_suggestions.isNotEmpty)
            ..._suggestions.map(
              (suggestion) => ListTile(
                title: Text(suggestion.description),
                onTap: () => _selectLocation(suggestion),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Only an approximate public area is shared. Do not include your full address here.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.campaign_outlined),
            label: const Text('Post request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerServiceRequestEditScreen extends StatefulWidget {
  const CustomerServiceRequestEditScreen({
    super.key,
    required this.requestId,
    required this.initialData,
    this.photoPicker,
    this.photoUploader,
    this.selectedPhotoBuilder,
  });

  final String requestId;
  final Map<String, dynamic> initialData;
  final ServiceRequestPhotoPicker? photoPicker;
  final ServiceRequestPhotoUploader? photoUploader;
  final ServiceRequestSelectedPhotoBuilder? selectedPhotoBuilder;

  @override
  State<CustomerServiceRequestEditScreen> createState() =>
      _CustomerServiceRequestEditScreenState();
}

class _CustomerServiceRequestEditScreenState
    extends State<CustomerServiceRequestEditScreen> {
  static const _maxPhotos = 3;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _budgetController;
  late final TextEditingController _locationController;
  final _addressSearch = AddressSearchService();
  final _picker = ImagePicker();

  late String _category;
  double? _latitude;
  double? _longitude;
  bool _isSaving = false;
  bool _isPickingPhoto = false;
  List<AddressResult> _suggestions = [];
  late List<String> _existingPhotoUrls;
  final List<String> _removedPhotoUrls = [];
  final List<XFile> _selectedPhotos = [];

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    _category = safeText(data['category'], serviceRequestCategories.first);
    if (!serviceRequestCategories.contains(_category)) {
      _category = serviceRequestCategories.first;
    }
    _titleController = TextEditingController(text: safeText(data['title'], ''));
    _descriptionController = TextEditingController(
      text: safeText(data['description'] ?? data['details'], ''),
    );
    _scheduleController = TextEditingController(
      text: safeText(data['scheduleText'] ?? data['neededBy'], ''),
    );
    _budgetController = TextEditingController(
      text: safeText(data['budgetText'] ?? data['budget'], ''),
    );
    _locationController = TextEditingController(
      text: ServiceRequestMarketplace.publicLocation(data),
    );
    _latitude = (data['approxLatitude'] as num?)?.toDouble();
    _longitude = (data['approxLongitude'] as num?)?.toDouble();
    _existingPhotoUrls = List<String>.of(
      ServiceRequestMarketplace.imageUrls(data),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _scheduleController.dispose();
    _budgetController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  int get _photoCount => _existingPhotoUrls.length + _selectedPhotos.length;

  Future<void> _searchLocation(String query) async {
    _latitude = null;
    _longitude = null;
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    final results = await _addressSearch.search(trimmed);
    if (!mounted) return;
    setState(() => _suggestions = results.take(5).toList());
  }

  Future<void> _selectLocation(AddressResult suggestion) async {
    final coords = await _addressSearch.getCoordinates(suggestion.placeId);
    if (!mounted || coords == null) return;

    setState(() {
      _locationController.text = _publicArea(suggestion.description);
      _latitude = _softCoordinate(coords['lat'] ?? 0);
      _longitude = _softCoordinate(coords['lng'] ?? 0);
      _suggestions = [];
    });
  }

  Future<void> _pickPhoto() async {
    if (_photoCount >= _maxPhotos) {
      _showSnack('You can add up to $_maxPhotos photos.');
      return;
    }
    if (_isPickingPhoto) return;

    setState(() => _isPickingPhoto = true);
    try {
      final picked =
          widget.photoPicker?.call() ??
          _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 78,
            maxWidth: 1600,
          );
      final photo = await picked;
      if (!mounted || photo == null) return;
      if (_photoCount >= _maxPhotos) {
        _showSnack('You can add up to $_maxPhotos photos.');
        return;
      }
      setState(() => _selectedPhotos.add(photo));
    } catch (_) {
      if (!mounted) return;
      _showSnack('We could not add that photo. Please try again.');
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  void _removeExistingPhoto(int index) {
    if (index < 0 || index >= _existingPhotoUrls.length) return;
    setState(() {
      _removedPhotoUrls.add(_existingPhotoUrls.removeAt(index));
    });
  }

  void _removeNewPhoto(int index) {
    if (index < 0 || index >= _selectedPhotos.length) return;
    setState(() => _selectedPhotos.removeAt(index));
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _showSnack('Please sign in to edit this request.');
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final schedule = _scheduleController.text.trim();
    final location = _locationController.text.trim();
    if (title.isEmpty ||
        description.isEmpty ||
        schedule.isEmpty ||
        location.isEmpty ||
        _latitude == null ||
        _longitude == null) {
      _showSnack('Add what you need, roughly where, and when.');
      return;
    }
    if (_photoCount > _maxPhotos) {
      _showSnack('You can add up to $_maxPhotos photos.');
      return;
    }

    setState(() => _isSaving = true);
    var uploadedUrls = <String>[];
    try {
      final uploader = widget.photoUploader ?? _uploadServiceRequestPhotos;
      if (_selectedPhotos.isNotEmpty) {
        uploadedUrls = await uploader(
          requestId: widget.requestId,
          userId: user.uid,
          photos: List<XFile>.unmodifiable(_selectedPhotos),
        );
      }

      final nextImageUrls = [..._existingPhotoUrls, ...uploadedUrls];
      await ServiceRequestCommands().updateCustomerRequest(
        requestId: widget.requestId,
        category: _category,
        title: title,
        description: description,
        scheduleText: schedule,
        publicLocation: location,
        approxLatitude: _latitude!,
        approxLongitude: _longitude!,
        budgetText: _budgetController.text,
        imageUrls: nextImageUrls,
      );

      for (final url in _removedPhotoUrls) {
        await _deleteServiceRequestPhotoUrl(url);
      }

      await LocalLinkAnalytics.instance.logEvent(
        'service_request_edit_completed',
        {'category': _category},
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      for (final url in uploadedUrls) {
        await _deleteServiceRequestPhotoUrl(url);
      }
      if (!mounted) return;
      _showSnack('We could not save your changes. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _softCoordinate(double value) =>
      double.parse(value.toStringAsFixed(3));

  String _publicArea(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return value.trim();
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edit request'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: serviceRequestCategories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value != null) setState(() => _category = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What do you need?'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            enabled: !_isSaving,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Details'),
          ),
          const SizedBox(height: 12),
          _EditableServiceRequestPhotos(
            existingPhotoUrls: _existingPhotoUrls,
            newPhotos: _selectedPhotos,
            maxPhotos: _maxPhotos,
            isPicking: _isPickingPhoto,
            onAdd: _isSaving ? null : _pickPhoto,
            onRemoveExisting: _isSaving ? null : _removeExistingPhoto,
            onRemoveNew: _isSaving ? null : _removeNewPhoto,
            thumbnailBuilder: widget.selectedPhotoBuilder,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _scheduleController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'When?'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _budgetController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Budget or rate expectation (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            enabled: !_isSaving,
            onChanged: _searchLocation,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Approximate area',
              hintText: 'Burntwood',
            ),
          ),
          if (_suggestions.isNotEmpty)
            ..._suggestions.map(
              (suggestion) => ListTile(
                title: Text(suggestion.description),
                onTap: _isSaving ? null : () => _selectLocation(suggestion),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Only an approximate public area is shared. Do not include your full address here.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerServiceRequestDetailScreen extends StatelessWidget {
  const CustomerServiceRequestDetailScreen({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(requestId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Service request'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            assert(() {
              debugPrint(
                'customer serviceRequest detail query failed: ${snapshot.error}',
              );
              return true;
            }());
            return const _MessageState(
              title: 'Unable to load request',
              message: 'Please try again in a moment.',
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists || snapshot.data!.data() == null) {
            return const _MessageState(
              title: 'Request unavailable',
              message: 'This request could not be found.',
            );
          }

          final data = snapshot.data!.data()!;
          final user = FirebaseAuth.instance.currentUser;
          final isOwner = user != null && data['customerId'] == user.uid;
          final now = DateTime.now();
          final isOpen = ServiceRequestMarketplace.isOpenForDiscovery(
            data,
            now: now,
          );
          final expiresAt = ServiceRequestMarketplace.asDateTime(
            data['expiresAt'],
          );

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _RequestSummary(data: data, isOpen: isOpen, expiresAt: expiresAt),
              if (isOwner) ...[
                const SizedBox(height: 14),
                _OwnerActions(requestId: requestId, data: data),
                const SizedBox(height: 24),
                _OfferList(requestId: requestId, request: data),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PhotoPickerField extends StatelessWidget {
  const _PhotoPickerField({
    required this.photos,
    required this.maxPhotos,
    required this.isPicking,
    required this.onAdd,
    required this.onRemove,
    this.thumbnailBuilder,
  });

  final List<XFile> photos;
  final int maxPhotos;
  final bool isPicking;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ServiceRequestSelectedPhotoBuilder? thumbnailBuilder;

  @override
  Widget build(BuildContext context) {
    final atLimit = photos.length >= maxPhotos;

    return Container(
      key: const ValueKey('service-request-photo-picker'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add photos (optional)',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Help local businesses understand what you need.',
            style: TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            thumbnailBuilder?.call(
                              context,
                              photos[index],
                              index,
                            ) ??
                            Image.file(
                              File(photos[index].path),
                              width: 104,
                              height: 88,
                              fit: BoxFit.cover,
                            ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filledTonal(
                          key: ValueKey('remove-service-request-photo-$index'),
                          onPressed: () => onRemove(index),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove photo',
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('add-service-request-photo'),
            onPressed: isPicking || atLimit ? null : onAdd,
            icon: isPicking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              atLimit ? 'Maximum $maxPhotos photos added' : 'Add photos',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${photos.length}/$maxPhotos photos selected. Avoid including personal information in photos.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableServiceRequestPhotos extends StatelessWidget {
  const _EditableServiceRequestPhotos({
    required this.existingPhotoUrls,
    required this.newPhotos,
    required this.maxPhotos,
    required this.isPicking,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    this.thumbnailBuilder,
  });

  final List<String> existingPhotoUrls;
  final List<XFile> newPhotos;
  final int maxPhotos;
  final bool isPicking;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemoveExisting;
  final ValueChanged<int>? onRemoveNew;
  final ServiceRequestSelectedPhotoBuilder? thumbnailBuilder;

  @override
  Widget build(BuildContext context) {
    final photoCount = existingPhotoUrls.length + newPhotos.length;
    final atLimit = photoCount >= maxPhotos;

    return Container(
      key: const ValueKey('service-request-edit-photo-picker'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Photos',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Help local businesses understand what you need.',
            style: TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (photoCount > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photoCount,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final isExisting = index < existingPhotoUrls.length;
                  final newPhotoIndex = index - existingPhotoUrls.length;
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 104,
                          height: 88,
                          child: isExisting
                              ? LocalLinkImage(
                                  imageUrl: existingPhotoUrls[index],
                                  aspectRatio: 104 / 88,
                                  fallbackIcon:
                                      Icons.image_not_supported_outlined,
                                  accentColor: AppColors.serviceGreen,
                                  semanticLabel: 'Existing request photo',
                                )
                              : thumbnailBuilder?.call(
                                      context,
                                      newPhotos[newPhotoIndex],
                                      newPhotoIndex,
                                    ) ??
                                    Image.file(
                                      File(newPhotos[newPhotoIndex].path),
                                      width: 104,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filledTonal(
                          key: ValueKey('remove-edit-request-photo-$index'),
                          onPressed: isExisting
                              ? onRemoveExisting == null
                                    ? null
                                    : () => onRemoveExisting!(index)
                              : onRemoveNew == null
                              ? null
                              : () => onRemoveNew!(newPhotoIndex),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove photo',
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('add-service-request-edit-photo'),
            onPressed: isPicking || atLimit ? null : onAdd,
            icon: isPicking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              atLimit ? 'Maximum $maxPhotos photos added' : 'Add photo',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$photoCount/$maxPhotos photos selected. Avoid including personal information in photos.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestSummary extends StatelessWidget {
  const _RequestSummary({
    required this.data,
    required this.isOpen,
    required this.expiresAt,
  });

  final Map<String, dynamic> data;
  final bool isOpen;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final title = safeText(data['title'], 'Request for help');
    final category = safeText(data['category'], 'Service');
    final location = ServiceRequestMarketplace.publicLocation(data);
    final schedule = safeText(data['scheduleText'], '');
    final description = safeText(data['description'] ?? data['details'], '');
    final budget = safeText(data['budgetText'] ?? data['budget'], '');
    final imageUrls = ServiceRequestMarketplace.imageUrls(data);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              _Chip(
                label: isOpen ? 'OPEN' : 'CLOSED',
                color: AppColors.serviceGreen,
              ),
              _Chip(label: category, color: AppColors.charcoal),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [location, schedule].where((value) => value.isNotEmpty).join(' · '),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.charcoal,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (budget.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              budget,
              style: const TextStyle(
                color: AppColors.serviceGreen,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            ServiceRequestPhotoStrip(imageUrls: imageUrls),
          ],
          if (expiresAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Expires ${expiresAt!.day}/${expiresAt!.month}/${expiresAt!.year}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnerActions extends StatelessWidget {
  const _OwnerActions({required this.requestId, required this.data});

  final String requestId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final isOpen = ServiceRequestMarketplace.isOpenForDiscovery(
      data,
      now: DateTime.now(),
    );
    final commands = ServiceRequestCommands();

    if (!isOpen) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => commands.renewRequest(requestId),
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Renew for 72 hours'),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => commands.closeRequest(
                  requestId,
                  status: ServiceRequestMarketplace.statusFilled,
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark filled'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => commands.closeRequest(
                  requestId,
                  status: ServiceRequestMarketplace.statusClosed,
                ),
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    await LocalLinkAnalytics.instance.logEvent('service_request_edit_started', {
      'category': safeText(data['category'], ''),
    });
    if (!context.mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerServiceRequestEditScreen(
          requestId: requestId,
          initialData: data,
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    try {
      await LocalLinkShareService().shareItem(
        item: LocalLinkShareItem(
          type: LocalLinkShareItemType.serviceRequest,
          id: requestId,
          data: data,
        ),
        sharePositionOrigin: _shareOrigin(context),
      );
      await LocalLinkAnalytics.instance.logEvent('service_request_shared', {
        'category': safeText(data['category'], ''),
      });
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing could not be started.')),
      );
    }
  }
}

class _OfferList extends StatelessWidget {
  const _OfferList({required this.requestId, required this.request});

  final String requestId;
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final offersRef = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(requestId)
        .collection('offers')
        .where('status', isEqualTo: ServiceRequestMarketplace.offerActive);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: offersRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          assert(() {
            debugPrint(
              'customer serviceRequest offers query failed: ${snapshot.error}',
            );
            return true;
          }());
          return const _MessageState(
            title: 'Unable to load offers',
            message: 'Please try again in a moment.',
          );
        }

        final offers = snapshot.data?.docs ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offers (${offers.length})',
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else if (offers.isEmpty)
              const _MessageState(
                title: 'No offers yet',
                message: 'Matching local providers can send offers here.',
              )
            else
              ...offers.map(
                (offer) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OfferCard(
                    requestId: requestId,
                    request: request,
                    offer: offer,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.requestId,
    required this.request,
    required this.offer,
  });

  final String requestId;
  final Map<String, dynamic> request;
  final QueryDocumentSnapshot<Map<String, dynamic>> offer;

  Future<void> _accept(BuildContext context) async {
    final data = offer.data();
    final businessId = safeText(data['businessId'], offer.id);
    final serviceId = safeText(data['serviceId'], '');
    if (businessId.isEmpty || serviceId.isEmpty) return;

    try {
      await ServiceRequestCommands().acceptOffer(
        requestId: requestId,
        businessId: businessId,
      );
      final conversationId = await BookingMessagingService()
          .createServiceEnquiry(
            businessId: businessId,
            serviceId: serviceId,
            text:
                'I would like to discuss your offer for my LocalLink request.',
          );

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookingConversationScreen(
            conversationId: conversationId,
            viewerType: 'customer',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not accept this offer.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = offer.data();
    final businessId = safeText(data['businessId'], offer.id);
    final businessName = safeText(data['businessName'], 'Business');
    final serviceName = safeText(data['serviceName'], 'Service');
    final price = safeText(data['priceText'], '');
    final proposedSchedule = safeText(data['proposedScheduleText'], '');
    final message = safeText(data['message'], '');

    if (businessId.isNotEmpty) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .get(),
        builder: (context, snapshot) {
          final business = snapshot.data?.data();
          final distance = business == null
              ? null
              : ServiceRequestMarketplace.distanceMiles(
                  request['approxLatitude'],
                  request['approxLongitude'],
                  business['latitude'],
                  business['longitude'],
                );
          return _OfferCardContent(
            businessId: businessId,
            businessName: businessName,
            serviceName: serviceName,
            distanceMiles: distance,
            price: price,
            proposedSchedule: proposedSchedule,
            message: message,
            onAccept: () => _accept(context),
          );
        },
      );
    }

    return _OfferCardContent(
      businessId: businessId,
      businessName: businessName,
      serviceName: serviceName,
      price: price,
      proposedSchedule: proposedSchedule,
      message: message,
      onAccept: () => _accept(context),
    );
  }
}

class _OfferCardContent extends StatelessWidget {
  const _OfferCardContent({
    required this.businessId,
    required this.businessName,
    required this.serviceName,
    required this.price,
    required this.proposedSchedule,
    required this.message,
    required this.onAccept,
    this.distanceMiles,
  });

  final String businessId;
  final String businessName;
  final String serviceName;
  final String price;
  final String proposedSchedule;
  final String message;
  final VoidCallback onAccept;
  final double? distanceMiles;

  @override
  Widget build(BuildContext context) {
    final serviceLine = [
      serviceName,
      if (distanceMiles != null) '${distanceMiles!.toStringAsFixed(1)} mi',
    ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            businessName,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            serviceLine,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (price.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              price,
              style: const TextStyle(
                color: AppColors.serviceGreen,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (proposedSchedule.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              proposedSchedule,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.charcoal,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: businessId.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BusinessDetailScreen(businessId: businessId),
                            ),
                          );
                        },
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('View business'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.serviceGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
