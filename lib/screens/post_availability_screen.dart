import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/business_access_service.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import 'add_service_screen.dart';

enum AvailabilityPostType { exact, window, flexible }

class PostAvailabilityScreen extends StatefulWidget {
  final String businessId;
  final String? initialServiceId;

  const PostAvailabilityScreen({
    super.key,
    required this.businessId,
    this.initialServiceId,
  });

  @override
  State<PostAvailabilityScreen> createState() => _PostAvailabilityScreenState();
}

class _PostAvailabilityScreenState extends State<PostAvailabilityScreen> {
  final messageController = TextEditingController();
  final priceController = TextEditingController();
  final capacityController = TextEditingController(text: '1');

  AvailabilityPostType type = AvailabilityPostType.exact;
  String? selectedServiceId;
  String? serviceIdToSelect;
  Map<String, dynamic>? selectedService;
  DateTime selectedDate = DateTime.now();
  TimeOfDay startTime = TimeOfDay.now();
  TimeOfDay? endTime;
  DateTime availableUntil = DateTime.now().add(const Duration(days: 7));
  bool isSaving = false;
  late Future<DocumentSnapshot<Map<String, dynamic>>> _businessFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>> _servicesFuture;

  @override
  void initState() {
    super.initState();
    serviceIdToSelect = widget.initialServiceId;
    _loadPageData();
  }

  @override
  void dispose() {
    messageController.dispose();
    priceController.dispose();
    capacityController.dispose();
    super.dispose();
  }

  void _loadPageData() {
    final businessRef = FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId);

    _businessFuture = businessRef.get().timeout(const Duration(seconds: 15));
    _servicesFuture = businessRef
        .collection('services')
        .where('isActive', isEqualTo: true)
        .get()
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );

    if (picked == null || !mounted) return;
    setState(() => selectedDate = picked);
  }

  Future<void> _pickAvailableUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: availableUntil,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );

    if (picked == null || !mounted) return;
    setState(() => availableUntil = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: startTime,
    );

    if (picked == null || !mounted) return;
    setState(() => startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final fallbackEndHour = startTime.hour >= 23 ? 23 : startTime.hour + 1;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          endTime ?? TimeOfDay(hour: fallbackEndHour, minute: startTime.minute),
    );

    if (picked == null || !mounted) return;
    setState(() => endTime = picked);
  }

  DateTime _dateWithTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int? _priceInPence() {
    final text = priceController.text.trim();
    if (text.isEmpty) {
      final servicePrice = selectedService?['price'];
      return servicePrice is num ? servicePrice.round() : null;
    }

    final pounds = double.tryParse(text);
    if (pounds == null || pounds < 0) return null;
    return (pounds * 100).round();
  }

  String _typeValue() {
    switch (type) {
      case AvailabilityPostType.exact:
        return 'exact';
      case AvailabilityPostType.window:
        return 'window';
      case AvailabilityPostType.flexible:
        return 'flexible';
    }
  }

  String _typeTitle(AvailabilityPostType value) {
    switch (value) {
      case AvailabilityPostType.exact:
        return 'Exact';
      case AvailabilityPostType.window:
        return 'Window';
      case AvailabilityPostType.flexible:
        return 'Flexible';
    }
  }

  String _typeSubtitle(AvailabilityPostType value) {
    switch (value) {
      case AvailabilityPostType.exact:
        return 'A single time people can book.';
      case AvailabilityPostType.window:
        return 'A wider time range, useful for several jobs or visits.';
      case AvailabilityPostType.flexible:
        return 'People ask for a time and you agree it together.';
    }
  }

  IconData _typeIcon(AvailabilityPostType value) {
    switch (value) {
      case AvailabilityPostType.exact:
        return Icons.event_available_outlined;
      case AvailabilityPostType.window:
        return Icons.view_timeline_outlined;
      case AvailabilityPostType.flexible:
        return Icons.auto_awesome_motion_outlined;
    }
  }

  String _messageHint() {
    final serviceName = safeText(selectedService?['name'], 'your service');

    switch (type) {
      case AvailabilityPostType.exact:
        return 'A space has opened up for $serviceName.';
      case AvailabilityPostType.window:
        return 'I have a few spaces available for $serviceName.';
      case AvailabilityPostType.flexible:
        return 'I have availability for $serviceName this week.';
    }
  }

  String _publishErrorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'We could not link this time to your Page just now. Open Your Page or check your access, then try again.';
      }

      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return 'We could not reach LocalLink just now. Please check your connection and try again.';
      }

      if (error.code == 'unauthenticated') {
        return 'Your session has expired. Please sign in again before sharing your time.';
      }
    }

    return 'We could not publish your time just now. Please try again.';
  }

  String _loadErrorMessage(Object? error) {
    if (error is TimeoutException) {
      return 'Services are taking longer than expected to load. Please try again, or open Services to check your Page setup.';
    }

    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'This Page is not linked to your profile yet. Open Your Page or check your access, then try again.';
      }

      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return 'We could not reach LocalLink just now. Please check your connection and try again.';
      }
    }

    return 'Please check your connection and try again.';
  }

  void _retryLoad() {
    setState(_loadPageData);
  }

  void _selectInitialServiceIfNeeded(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> services,
  ) {
    final pendingServiceId = serviceIdToSelect;

    if (pendingServiceId == null) {
      return;
    }

    for (final service in services) {
      if (service.id == pendingServiceId) {
        selectedServiceId = service.id;
        selectedService = service.data();
        serviceIdToSelect = null;
        return;
      }
    }
  }

  Future<void> _openAddService() async {
    final result = await Navigator.push<AddServiceResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddServiceScreen(businessId: widget.businessId),
      ),
    );

    if (!mounted) return;

    if (result?.nextStep == AddServiceNextStep.shareNow) {
      setState(() {
        serviceIdToSelect = result!.serviceId;
        selectedServiceId = null;
        selectedService = null;
        _loadPageData();
      });
      return;
    }

    _retryLoad();
  }

  Future<void> _publish(Map<String, dynamic> businessData) async {
    final user = FirebaseAuth.instance.currentUser;
    final service = selectedService;
    final serviceId = selectedServiceId;
    final message = messageController.text.trim();
    final price = _priceInPence();
    final capacity = int.tryParse(capacityController.text.trim()) ?? 1;

    if (user == null) return;

    if (service == null || serviceId == null) {
      _showSnack('Choose a service first.');
      return;
    }

    if (message.isEmpty) {
      _showSnack('Add a short note so people understand what is available.');
      return;
    }

    if (price == null) {
      if (priceController.text.trim().isEmpty) {
        _showSnack(
          'Add a price for this time, or add a default price to the service.',
        );
      } else {
        _showSnack('Enter a valid price.');
      }
      return;
    }

    if (capacity < 1) {
      _showSnack('Add at least 1 space.');
      return;
    }

    final canPost = await BusinessAccessService.canPostForBusiness(
      businessId: widget.businessId,
      businessData: businessData,
    );

    if (!canPost) {
      _showSnack(
        'This Page is not linked to your profile yet. Create or claim a Page first, then share your time.',
      );
      return;
    }

    final duration = (service['durationMinutes'] as num?)?.toInt();
    final start = _dateWithTime(selectedDate, startTime);
    DateTime? end;
    DateTime availableFrom = start;
    DateTime expiresAt = start;

    if (type == AvailabilityPostType.exact) {
      end = endTime == null
          ? start.add(Duration(minutes: duration ?? 30))
          : _dateWithTime(selectedDate, endTime!);
    } else if (type == AvailabilityPostType.window) {
      if (endTime == null) {
        _showSnack('Choose when you finish.');
        return;
      }
      end = _dateWithTime(selectedDate, endTime!);
    } else {
      availableFrom = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      end = DateTime(
        availableUntil.year,
        availableUntil.month,
        availableUntil.day,
        23,
        59,
      );
      expiresAt = end;
    }

    if (end.isBefore(start) || end.isAtSameMomentAs(start)) {
      _showSnack('The end time must be after the start time.');
      return;
    }

    if (type != AvailabilityPostType.flexible &&
        start.isBefore(DateTime.now())) {
      _showSnack('Choose a future time.');
      return;
    }

    setState(() => isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('availabilityPosts').add({
        'businessId': widget.businessId,
        'availabilityId': '',
        'businessOwnerId': user.uid,
        'businessName': safeText(businessData['businessName'], 'Business'),
        'serviceId': serviceId,
        'serviceName': safeText(service['name'], 'Service'),
        'serviceDetails': safeText(service['details'], ''),
        'type': _typeValue(),
        'availabilityType': _typeValue(),
        'description': message,
        'message': message,
        'availabilityAt': Timestamp.fromDate(availableFrom),
        'startTime': Timestamp.fromDate(start),
        'startDateTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'endDateTime': Timestamp.fromDate(end),
        'availableFrom': Timestamp.fromDate(availableFrom),
        'availableUntil': Timestamp.fromDate(end),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'durationMinutes': duration,
        'capacity': capacity,
        'remainingCapacity': capacity,
        'price': price,
        'priceOverride': price,
        'category': safeText(
          service['category'] ?? businessData['category'],
          '',
        ),
        'location': safeText(
          businessData['address'] ?? businessData['location'],
          '',
        ),
        'latitude': businessData['latitude'],
        'longitude': businessData['longitude'],
        'staffId': null,
        'staffName': null,
        'slotId': null,
        'slotPath': null,
        'status': 'live',
        'isActive': true,
        'archived': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your time is now visible to nearby people.'),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;

      _showSnack(_publishErrorMessage(error));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _businessFuture,
      builder: (context, businessSnapshot) {
        final businessData = businessSnapshot.data?.data() ?? {};

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Share available time'),
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.charcoal,
            elevation: 0,
          ),
          body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: _servicesFuture,
            builder: (context, serviceSnapshot) {
              if (businessSnapshot.hasData && !businessSnapshot.data!.exists) {
                return _PostAvailabilityMessage(
                  icon: Icons.storefront_outlined,
                  title: 'We could not find this Page',
                  message:
                      'Open Your Page again, then try sharing available time.',
                  actionLabel: 'Retry',
                  onAction: _retryLoad,
                );
              }

              if (serviceSnapshot.hasError || businessSnapshot.hasError) {
                return _PostAvailabilityMessage(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load services',
                  message: _loadErrorMessage(
                    serviceSnapshot.error ?? businessSnapshot.error,
                  ),
                  actionLabel: 'Retry',
                  onAction: _retryLoad,
                );
              }

              if (!serviceSnapshot.hasData ||
                  businessSnapshot.connectionState == ConnectionState.waiting) {
                return const _PostAvailabilityLoading();
              }

              final services = serviceSnapshot.data!.docs;
              _selectInitialServiceIfNeeded(services);

              if (services.isEmpty) {
                return _PostAvailabilityMessage(
                  icon: Icons.handyman_outlined,
                  title:
                      'Add your first service before sharing available time.',
                  message: 'Services are what people can book from your Page.',
                  actionLabel: 'Add service',
                  onAction: _openAddService,
                );
              }

              return ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                children: [
                  _PostAvailabilityHero(
                    serviceName: safeText(selectedService?['name'], ''),
                  ),
                  const SizedBox(height: 22),
                  _PostSection(
                    title: 'Service',
                    subtitle: 'Choose what this available time is for.',
                    icon: Icons.design_services_outlined,
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedServiceId,
                      decoration: const InputDecoration(
                        labelText: 'Service',
                        hintText: 'Select a service',
                        border: OutlineInputBorder(),
                      ),
                      items: services.map((doc) {
                        final data = doc.data();
                        return DropdownMenuItem(
                          value: doc.id,
                          child: Text(safeText(data['name'], 'Service')),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final doc = services.firstWhere(
                          (doc) => doc.id == value,
                        );
                        setState(() {
                          selectedServiceId = doc.id;
                          selectedService = doc.data();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PostSection(
                    title: 'Available time',
                    subtitle: 'Pick the shape that best matches your day.',
                    icon: Icons.schedule_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<AvailabilityPostType>(
                            showSelectedIcon: false,
                            segments: AvailabilityPostType.values.map((value) {
                              return ButtonSegment(
                                value: value,
                                icon: Icon(_typeIcon(value), size: 18),
                                label: Text(_typeTitle(value)),
                              );
                            }).toList(),
                            selected: {type},
                            onSelectionChanged: (selection) {
                              setState(() => type = selection.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        _HelperText(
                          icon: _typeIcon(type),
                          text: _typeSubtitle(type),
                        ),
                        const SizedBox(height: 16),
                        _PickerButton(
                          onPressed: _pickDate,
                          icon: Icons.calendar_today_outlined,
                          label: type == AvailabilityPostType.flexible
                              ? 'Available from'
                              : 'Date',
                          value:
                              '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        ),
                        const SizedBox(height: 12),
                        if (type != AvailabilityPostType.flexible) ...[
                          _PickerButton(
                            onPressed: _pickStartTime,
                            icon: Icons.schedule_outlined,
                            label: 'Start',
                            value: startTime.format(context),
                          ),
                          const SizedBox(height: 12),
                          _PickerButton(
                            onPressed: _pickEndTime,
                            icon: Icons.timelapse_outlined,
                            label: type == AvailabilityPostType.window
                                ? 'Finish'
                                : 'Finish',
                            value: endTime == null
                                ? type == AvailabilityPostType.window
                                      ? 'Choose a time'
                                      : 'Optional'
                                : endTime!.format(context),
                          ),
                        ] else ...[
                          _PickerButton(
                            onPressed: _pickAvailableUntil,
                            icon: Icons.event_available_outlined,
                            label: 'Available until',
                            value:
                                '${availableUntil.day}/${availableUntil.month}/${availableUntil.year}',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: capacityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Spaces available',
                              helperText:
                                  'Leave this as 1 unless several people can book.',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PostSection(
                    title: 'Details',
                    subtitle: 'A short note helps people decide quickly.',
                    icon: Icons.notes_outlined,
                    child: Column(
                      children: [
                        TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Price',
                            hintText: selectedService == null
                                ? 'Leave blank to use your service price'
                                : 'Default ${formatPrice(selectedService!['price'])}',
                            helperText:
                                'Only add a price here if this time is different.',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: messageController,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Short note',
                            hintText: _messageHint(),
                            helperText:
                                'Keep it simple: what is available and anything useful to know.',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : () => _publish(businessData),
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.campaign_outlined),
                      label: Text(
                        isSaving
                            ? 'Sharing your available time...'
                            : 'Share available time',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.serviceGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PostAvailabilityLoading extends StatelessWidget {
  const _PostAvailabilityLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 16),
            Text(
              'Preparing your services...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'This usually takes a few seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostAvailabilityHero extends StatelessWidget {
  final String serviceName;

  const _PostAvailabilityHero({required this.serviceName});

  @override
  Widget build(BuildContext context) {
    final hasService = serviceName.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.serviceGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.event_available_rounded,
            color: AppColors.serviceGreen,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Share available time',
          style: TextStyle(
            color: AppColors.charcoal,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasService
              ? 'Share a clear, bookable opening for $serviceName.'
              : 'Tell nearby people when they can book you. Keep it short and clear.',
          style: const TextStyle(
            color: AppColors.textMuted,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PostSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _PostSection({
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

class _HelperText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HelperText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PickerButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final String value;

  const _PickerButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: AppColors.charcoal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.serviceGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _PostAvailabilityMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PostAvailabilityMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.serviceGreen),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
