import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/address_result.dart';
import '../services/address_search_service.dart';
import '../services/booking_messaging_service.dart';
import '../services/service_request_marketplace.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import 'booking_conversation_screen.dart';
import 'business_detail_screen.dart';

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

class CustomerServiceRequestScreen extends StatefulWidget {
  const CustomerServiceRequestScreen({super.key});

  @override
  State<CustomerServiceRequestScreen> createState() =>
      _CustomerServiceRequestScreenState();
}

class _CustomerServiceRequestScreenState
    extends State<CustomerServiceRequestScreen> {
  final _titleController = TextEditingController(text: 'Cleaner needed');
  final _descriptionController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _budgetController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressSearch = AddressSearchService();

  String _category = 'Cleaner';
  double? _latitude;
  double? _longitude;
  bool _isSaving = false;
  List<AddressResult> _suggestions = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _scheduleController.dispose();
    _budgetController.dispose();
    _locationController.dispose();
    super.dispose();
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
    try {
      final request = await ServiceRequestCommands().createRequest(
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
      _showSnack('We could not post this request. Please try again.');
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
      return OutlinedButton.icon(
        onPressed: () => commands.renewRequest(requestId),
        icon: const Icon(Icons.refresh_outlined),
        label: const Text('Renew for 72 hours'),
      );
    }

    return Row(
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
    );
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
    required this.message,
    required this.onAccept,
    this.distanceMiles,
  });

  final String businessId;
  final String businessName;
  final String serviceName;
  final String price;
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
