import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:io';

import '../theme/app_colors.dart';

enum _DurationUnit { minutes, hours }

enum AddServiceNextStep { shareNow, backToPage }

class AddServiceResult {
  final String businessId;
  final String serviceId;
  final String serviceName;
  final AddServiceNextStep nextStep;

  const AddServiceResult({
    required this.businessId,
    required this.serviceId,
    required this.serviceName,
    required this.nextStep,
  });
}

class AddServiceScreen extends StatefulWidget {
  final String businessId;

  final String? serviceId;
  final Map<String, dynamic>? existingService;

  const AddServiceScreen({
    super.key,
    required this.businessId,
    this.serviceId,
    this.existingService,
  });

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  final nameController = TextEditingController();

  final priceController = TextEditingController();

  final durationController = TextEditingController();

  final detailsController = TextEditingController();

  final ImagePicker picker = ImagePicker();

  bool isSaving = false;

  File? selectedImage;

  String? imageUrl;

  _DurationUnit durationUnit = _DurationUnit.minutes;

  bool get isEditing => widget.serviceId != null;

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    durationController.dispose();
    detailsController.dispose();
    super.dispose();
  }

  // =====================================
  // INIT
  // =====================================

  @override
  void initState() {
    super.initState();

    final service = widget.existingService;

    if (service != null) {
      nameController.text = service['name'] ?? '';

      detailsController.text = service['details'] ?? '';

      final price = ((service['price'] ?? 0) as num).toDouble() / 100;

      priceController.text = price.toStringAsFixed(2);

      final durationMinutes = ((service['durationMinutes'] ?? 30) as num)
          .round();

      if (durationMinutes >= 60 && durationMinutes % 60 == 0) {
        durationUnit = _DurationUnit.hours;
        durationController.text = (durationMinutes ~/ 60).toString();
      } else {
        durationUnit = _DurationUnit.minutes;
        durationController.text = durationMinutes.toString();
      }

      imageUrl = service['imageUrl']?.toString();
    }
  }

  int? _durationInMinutes() {
    final value = double.tryParse(durationController.text.trim());

    if (value == null || value <= 0) return null;

    switch (durationUnit) {
      case _DurationUnit.minutes:
        return value.round();
      case _DurationUnit.hours:
        return (value * 60).round();
    }
  }

  void _resetForAnotherService() {
    setState(() {
      nameController.clear();
      priceController.clear();
      durationController.clear();
      detailsController.clear();
      selectedImage = null;
      imageUrl = null;
      durationUnit = _DurationUnit.minutes;
    });
  }

  Future<AddServiceNextStep?> _showServiceSavedSheet(String serviceName) {
    return showModalBottomSheet<AddServiceNextStep?>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Service added',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$serviceName is saved to your Page. Share a time next so customers can see when they can book it.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                _SavedActionTile(
                  icon: Icons.campaign_outlined,
                  title: 'Share this service now',
                  subtitle: 'Pick a time and make it visible to customers.',
                  color: AppColors.serviceGreen,
                  onTap: () =>
                      Navigator.pop(context, AddServiceNextStep.shareNow),
                ),
                const SizedBox(height: 10),
                _SavedActionTile(
                  icon: Icons.add_circle_outline,
                  title: 'Add another service',
                  subtitle: 'Keep building what your Page offers.',
                  color: AppColors.primary,
                  onTap: () => Navigator.pop(context, null),
                ),
                const SizedBox(height: 10),
                _SavedActionTile(
                  icon: Icons.storefront_outlined,
                  title: 'Back to Your Page',
                  subtitle: 'Return to your business tools.',
                  color: AppColors.charcoal,
                  onTap: () =>
                      Navigator.pop(context, AddServiceNextStep.backToPage),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> pickServiceImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (!mounted || picked == null) return;

    setState(() {
      selectedImage = File(picked.path);
    });
  }

  Future<String?> uploadServiceImage() async {
    if (selectedImage == null) return imageUrl;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('not-signed-in');
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance.ref().child(
      'servicePhotos/${widget.businessId}/$fileName',
    );

    assert(() {
      debugPrint('UPLOAD SERVICE IMAGE path=${ref.fullPath}');
      return true;
    }());

    await ref.putFile(
      selectedImage!,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'ownerId': user.uid, 'businessId': widget.businessId},
      ),
    );

    return ref.getDownloadURL();
  }

  List<String> _keywordsFor(String value) {
    final words =
        value
            .toLowerCase()
            .split(RegExp('[^a-z0-9]+'))
            .where((word) => word.length > 2)
            .toSet()
            .toList()
          ..sort();

    return words.take(32).toList();
  }

  // =====================================
  // SAVE SERVICE
  // =====================================

  Future<void> saveService() async {
    final name = nameController.text.trim();

    final details = detailsController.text.trim();

    final pounds = double.tryParse(priceController.text.trim());

    final duration = _durationInMinutes();

    if (name.isEmpty || pounds == null || duration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a service name, price and duration.'),
        ),
      );

      return;
    }

    if (pounds <= 0 || duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid price and duration.'),
        ),
      );

      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final priceInPence = (pounds * 100).round();
      final uploadedImageUrl = await uploadServiceImage();
      final businessSnap = await firestore
          .collection('businesses')
          .doc(widget.businessId)
          .get();
      final businessData = businessSnap.data() ?? {};
      final businessName = businessData['businessName']?.toString() ?? '';
      final businessCategory = businessData['category']?.toString() ?? '';

      final data = {
        'name': name,

        'details': details,

        'price': priceInPence,

        'durationMinutes': duration,

        'isActive': true,

        'businessId': widget.businessId,

        'businessName': businessName,

        'category': businessCategory,

        'searchKeywords': _keywordsFor(
          '$name $details $businessName $businessCategory',
        ),

        'updatedAt': FieldValue.serverTimestamp(),

        if (uploadedImageUrl != null && uploadedImageUrl.isNotEmpty)
          'imageUrl': uploadedImageUrl,
      };

      final servicesRef = firestore
          .collection('businesses')
          .doc(widget.businessId)
          .collection('services');

      assert(() {
        debugPrint('SAVE SERVICE collectionPath=${servicesRef.path}');
        debugPrint('SAVE SERVICE isEditing=$isEditing');
        return true;
      }());

      // =====================================
      // EDIT
      // =====================================

      String savedServiceId;

      if (isEditing) {
        final serviceRef = servicesRef.doc(widget.serviceId);
        savedServiceId = serviceRef.id;

        assert(() {
          debugPrint('SAVE SERVICE updatePath=${serviceRef.path}');
          return true;
        }());

        await serviceRef.update(data);

        assert(() {
          debugPrint('SAVE SERVICE update succeeded path=${serviceRef.path}');
          return true;
        }());
      }
      // =====================================
      // ADD
      // =====================================
      else {
        final serviceRef = servicesRef.doc();
        final createData = {...data, 'createdAt': Timestamp.now()};
        savedServiceId = serviceRef.id;

        assert(() {
          debugPrint('SAVE SERVICE createPath=${serviceRef.path}');
          return true;
        }());

        await serviceRef.set(createData);

        assert(() {
          debugPrint('SAVE SERVICE create succeeded path=${serviceRef.path}');
          return true;
        }());
      }

      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      if (isEditing) {
        Navigator.pop(context);
        return;
      }

      final nextStep = await _showServiceSavedSheet(name);

      if (!mounted) return;

      if (nextStep == null) {
        _resetForAnotherService();
        return;
      }

      Navigator.pop(
        context,
        AddServiceResult(
          businessId: widget.businessId,
          serviceId: savedServiceId,
          serviceName: name,
          nextStep: nextStep,
        ),
      );
    } on FirebaseException catch (error) {
      assert(() {
        debugPrint('SAVE SERVICE FirebaseException code=${error.code}');
        debugPrint('SAVE SERVICE FirebaseException plugin=${error.plugin}');
        return true;
      }());

      if (!mounted) return;

      final message = error.code == 'permission-denied'
          ? 'We could not save this service because your Page access needs refreshing. Please check your Page access and try again.'
          : 'We could not save that service just now. Please try again.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      assert(() {
        debugPrint('SAVE SERVICE error=$error');
        return true;
      }());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not save that service just now. Please try again.',
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        isSaving = false;
      });
    }
  }

  // =====================================
  // UI
  // =====================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit service' : 'Add service'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),

      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),

        children: [
          _ServiceEditorHeader(isEditing: isEditing),
          const SizedBox(height: 18),
          _ServiceImagePicker(
            selectedImage: selectedImage,
            imageUrl: imageUrl,
            onPick: isSaving ? null : pickServiceImage,
          ),

          const SizedBox(height: 16),

          _EditorSection(
            title: 'Service details',
            subtitle: 'Name what customers can book.',
            icon: Icons.design_services_outlined,
            child: Column(
              children: [
                _EditorTextField(
                  controller: nameController,
                  label: 'Service name',
                  hint: 'Dog walk, garden tidy, deep clean',
                  icon: Icons.handshake_outlined,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 14),
                _EditorTextField(
                  controller: detailsController,
                  label: 'What people get',
                  hint: 'Describe what is included.',
                  icon: Icons.notes_outlined,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _EditorSection(
            title: 'Price and duration',
            subtitle: 'Set a clear price and how long it takes.',
            icon: Icons.schedule_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditorTextField(
                  controller: priceController,
                  label: 'Price',
                  hint: '25.00',
                  icon: Icons.payments_outlined,
                  prefixText: '£ ',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _EditorTextField(
                        controller: durationController,
                        label: 'Duration',
                        hint: durationUnit == _DurationUnit.hours ? '1' : '60',
                        icon: Icons.timer_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 152,
                      child: SegmentedButton<_DurationUnit>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _DurationUnit.minutes,
                            label: Text('Mins'),
                            icon: Icon(Icons.timer_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: _DurationUnit.hours,
                            label: Text('Hours'),
                            icon: Icon(Icons.schedule_outlined, size: 18),
                          ),
                        ],
                        selected: {durationUnit},
                        onSelectionChanged: isSaving
                            ? null
                            : (selection) {
                                setState(() {
                                  durationUnit = selection.first;
                                });
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,

            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveService,
              icon: isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(isEditing ? 'Update service' : 'Save service'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.serviceGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SavedActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
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
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
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

class _ServiceEditorHeader extends StatelessWidget {
  final bool isEditing;

  const _ServiceEditorHeader({required this.isEditing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.serviceGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.handshake_outlined,
            color: AppColors.serviceGreen,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          isEditing ? 'Edit service' : 'Add a service',
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Services are what customers see when they book from your Page.',
          style: TextStyle(
            color: AppColors.textMuted,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EditorSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _EditorSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.serviceGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EditorTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? prefixText;
  final int minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;

  const _EditorTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.prefixText,
    this.minLines = 1,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        prefixIcon: Icon(icon, color: AppColors.serviceGreen),
        border: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.serviceGreen, width: 1.5),
        ),
      ),
    );
  }
}

class _ServiceImagePicker extends StatelessWidget {
  final File? selectedImage;
  final String? imageUrl;
  final VoidCallback? onPick;

  const _ServiceImagePicker({
    required this.selectedImage,
    required this.imageUrl,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final hasNetworkImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Semantics(
      button: true,
      label: 'Choose a service photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPick,
        child: Container(
          height: 172,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (selectedImage != null)
                Image.file(selectedImage!, fit: BoxFit.cover)
              else if (hasNetworkImage)
                Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const _ImagePlaceholder();
                  },
                )
              else
                const _ImagePlaceholder(),
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.charcoal.withValues(alpha: 0.76),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Choose Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 42,
          color: AppColors.textMuted,
        ),
        SizedBox(height: 8),
        Text(
          'Add a service photo',
          style: TextStyle(
            color: AppColors.charcoal,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Choose from your photos',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
