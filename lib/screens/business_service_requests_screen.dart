import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/service_request_marketplace.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import '../widgets/service_request_photos.dart';

typedef BusinessCustomerRequestContextLoader =
    Future<BusinessCustomerRequestContext> Function(String businessId);
typedef BusinessCustomerRequestStreamFactory =
    Stream<List<BusinessCustomerRequestItem>> Function();
typedef BusinessCustomerRequestSettingUpdater =
    Future<void> Function(String businessId, bool enabled);

class BusinessServiceRequestsScreen extends StatefulWidget {
  const BusinessServiceRequestsScreen({
    super.key,
    this.businessId,
    this.contextLoader,
    this.requestsStreamFactory,
    this.settingUpdater,
  });

  final String? businessId;
  final BusinessCustomerRequestContextLoader? contextLoader;
  final BusinessCustomerRequestStreamFactory? requestsStreamFactory;
  final BusinessCustomerRequestSettingUpdater? settingUpdater;

  @override
  State<BusinessServiceRequestsScreen> createState() =>
      _BusinessServiceRequestsScreenState();
}

class _BusinessServiceRequestsScreenState
    extends State<BusinessServiceRequestsScreen> {
  late Future<BusinessCustomerRequestContext> _contextFuture;

  @override
  void initState() {
    super.initState();
    _contextFuture = _loadContext();
  }

  @override
  void didUpdateWidget(BusinessServiceRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.contextLoader != widget.contextLoader) {
      _contextFuture = _loadContext();
    }
  }

  Future<BusinessCustomerRequestContext> _loadContext() {
    final businessId = widget.businessId;
    if (businessId == null || businessId.isEmpty) {
      return Future.value(BusinessCustomerRequestContext.missing());
    }
    final loader = widget.contextLoader ?? _loadBusinessCustomerRequestContext;
    return loader(businessId);
  }

  Future<void> _updateCustomerRequests(bool enabled) async {
    final businessId = widget.businessId;
    if (businessId == null || businessId.isEmpty) return;
    final updater =
        widget.settingUpdater ?? _updateBusinessCustomerRequestsSetting;
    await updater(businessId, enabled);
    if (!mounted) return;
    setState(() {
      _contextFuture = _loadContext();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('People Looking for Help'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: widget.businessId == null || widget.businessId!.isEmpty
          ? const _MessageState(
              icon: Icons.storefront_outlined,
              title: 'Choose a business first',
              message: 'Requests are matched to your active business services.',
            )
          : _MatchedRequestList(
              businessId: widget.businessId!,
              contextFuture: _contextFuture,
              requestsStreamFactory: widget.requestsStreamFactory,
              onToggleChanged: _updateCustomerRequests,
            ),
    );
  }
}

class _MatchedRequestList extends StatefulWidget {
  const _MatchedRequestList({
    required this.businessId,
    required this.contextFuture,
    required this.onToggleChanged,
    this.requestsStreamFactory,
  });

  final String businessId;
  final Future<BusinessCustomerRequestContext> contextFuture;
  final BusinessCustomerRequestStreamFactory? requestsStreamFactory;
  final Future<void> Function(bool enabled) onToggleChanged;

  @override
  State<_MatchedRequestList> createState() => _MatchedRequestListState();
}

class _MatchedRequestListState extends State<_MatchedRequestList> {
  bool _updatingSetting = false;
  String? _settingError;

  Future<void> _handleToggle(
    BusinessCustomerRequestContext offerContext,
    bool value,
  ) async {
    if (_updatingSetting) return;

    setState(() {
      _updatingSetting = true;
      _settingError = null;
    });

    try {
      await widget.onToggleChanged(value);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settingError =
            'Customer requests could not be updated. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingSetting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BusinessCustomerRequestContext>(
      future: widget.contextFuture,
      builder: (context, contextSnapshot) {
        if (contextSnapshot.hasError) {
          assert(() {
            debugPrint(
              'business customer request context failed: ${contextSnapshot.error}',
            );
            return true;
          }());
          return const _MessageState(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load customer requests',
            message: 'Please try again in a moment.',
          );
        }

        if (!contextSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final offerContext = contextSnapshot.data!;
        if (!offerContext.businessExists) {
          return const _MessageState(
            icon: Icons.storefront_outlined,
            title: 'Business unavailable',
            message: 'We could not load this business right now.',
          );
        }

        final requestsEnabled = offerContext.customerRequestsEnabled;
        return StreamBuilder<List<BusinessCustomerRequestItem>>(
          stream:
              widget.requestsStreamFactory?.call() ??
              _watchOpenCustomerRequests(),
          builder: (context, snapshot) {
            if (requestsEnabled &&
                snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final now = DateTime.now();
            final matches = (snapshot.data ?? const [])
                .map((doc) {
                  final service = offerContext.matchingServiceFor(doc.data);
                  if (service == null) return null;
                  return _MatchedRequest(item: doc, service: service);
                })
                .whereType<_MatchedRequest>()
                .where(
                  (match) => ServiceRequestMarketplace.isOpenForDiscovery(
                    match.item.data,
                    now: now,
                  ),
                )
                .toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _CustomerRequestsToggleCard(
                  enabled: requestsEnabled,
                  updating: _updatingSetting,
                  errorText: _settingError,
                  onChanged: (value) => _handleToggle(offerContext, value),
                ),
                const SizedBox(height: 18),
                if (!requestsEnabled)
                  const _InlineMessageState(
                    icon: Icons.pause_circle_outline,
                    title: 'Customer requests are paused',
                    message:
                        "Turn them back on whenever you'd like to see new requests from people nearby.",
                  )
                else if (!offerContext.isActive)
                  const _InlineMessageState(
                    icon: Icons.storefront_outlined,
                    title: 'Business page is not live',
                    message:
                        'Customer requests will appear when your business page is active.',
                  )
                else if (!offerContext.hasBusinessLocation)
                  const _InlineMessageState(
                    icon: Icons.location_off_outlined,
                    title: 'Business location needed',
                    message:
                        'Add an approximate business location so LocalLink can show nearby customer requests.',
                  )
                else if (snapshot.hasError)
                  const _InlineMessageState(
                    icon: Icons.error_outline_rounded,
                    title: 'Unable to load requests',
                    message: 'Please try again in a moment.',
                  )
                else ...[
                  const Text(
                    'Matching requests',
                    style: TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (matches.isEmpty)
                    const _InlineMessageState(
                      icon: Icons.search_off_rounded,
                      title: 'No matching requests right now',
                      message:
                          "We'll show them here when someone nearby is looking for a service you offer.",
                    )
                  else
                    ...matches.map(
                      (match) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ProviderRequestCard(
                          businessId: widget.businessId,
                          businessData: offerContext.businessData,
                          request: match.item,
                          service: match.service,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _ProviderRequestCard extends StatelessWidget {
  const _ProviderRequestCard({
    required this.businessId,
    required this.businessData,
    required this.request,
    required this.service,
  });

  final String businessId;
  final Map<String, dynamic> businessData;
  final BusinessCustomerRequestItem request;
  final BusinessCustomerRequestService service;

  Future<void> _showOfferSheet(BuildContext context) async {
    final requestRef = request.reference;
    if (requestRef == null) return;

    final existing = await requestRef
        .collection('offers')
        .doc(businessId)
        .get();
    if (!context.mounted) return;

    final data = existing.data() ?? const {};
    final priceController = TextEditingController(
      text: safeText(data['priceText'], ''),
    );
    final proposedScheduleController = TextEditingController(
      text: safeText(data['proposedScheduleText'], ''),
    );
    final messageController = TextEditingController(
      text: safeText(data['message'], ''),
    );
    final imageUrls = ServiceRequestMarketplace.imageUrls(request.data);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Offer your service',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (imageUrls.isNotEmpty) ...[
                  ServiceRequestPhotoStrip(imageUrls: imageUrls),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: priceController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Price or rate (optional)',
                    hintText: '£18/hour or quote after chat',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: proposedScheduleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Proposed time (optional)',
                    hintText: 'Friday morning or Tuesday at 2pm',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Short message (optional)',
                    hintText: 'I cover Burntwood and can do Friday mornings.',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, 'save'),
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Send offer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.serviceGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
                if (existing.exists &&
                    data['status'] != ServiceRequestMarketplace.offerWithdrawn)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, 'withdraw'),
                    icon: const Icon(Icons.undo_outlined),
                    label: const Text('Withdraw offer'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    final commands = ServiceRequestCommands();
    try {
      if (action == 'save') {
        await commands.upsertOffer(
          requestId: request.id,
          businessId: businessId,
          businessName: safeText(
            businessData['businessName'] ?? businessData['name'],
            'Business',
          ),
          serviceId: service.id,
          serviceName: safeText(service.data['name'], 'Service'),
          priceText: priceController.text,
          proposedScheduleText: proposedScheduleController.text,
          message: messageController.text,
        );
      } else if (action == 'withdraw') {
        await commands.withdrawOffer(
          requestId: request.id,
          businessId: businessId,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not update this offer.')),
      );
    } finally {
      priceController.dispose();
      proposedScheduleController.dispose();
      messageController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = request.data;
    final title = safeText(data['title'], 'Request for help');
    final details = safeText(data['description'] ?? data['details'], '');
    final location = ServiceRequestMarketplace.publicLocation(data);
    final schedule = safeText(data['scheduleText'] ?? data['neededBy'], '');
    final budget = safeText(data['budgetText'] ?? data['budget'], '');
    final imageUrls = ServiceRequestMarketplace.imageUrls(data);
    final distance = ServiceRequestMarketplace.distanceMiles(
      data['approxLatitude'],
      data['approxLongitude'],
      businessData['latitude'],
      businessData['longitude'],
    );

    final offerStream = request.reference
        ?.collection('offers')
        .doc(businessId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      stream: offerStream,
      builder: (context, snapshot) {
        final offer = snapshot.data?.data();
        final offerStatus = safeText(offer?['status'], '');
        final hasActiveOffer =
            offerStatus == ServiceRequestMarketplace.offerActive ||
            offerStatus == ServiceRequestMarketplace.offerAccepted;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusPill(
                    label: hasActiveOffer ? 'Offered' : 'Open',
                    color: hasActiveOffer
                        ? AppColors.serviceGreen
                        : AppColors.primary,
                  ),
                  if (imageUrls.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ServiceRequestPhotoPreview(imageUrls: imageUrls),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  safeText(data['category'], 'Service'),
                  location,
                  if (distance != null) '${distance.toStringAsFixed(1)} mi',
                ].where((value) => value.isNotEmpty).join(' · '),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (schedule.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  schedule,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (details.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  details,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    height: 1.34,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (budget.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  budget,
                  style: const TextStyle(
                    color: AppColors.serviceGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showOfferSheet(context),
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(
                    hasActiveOffer ? 'Edit offer' : 'Offer my service',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<BusinessCustomerRequestContext> _loadBusinessCustomerRequestContext(
  String businessId,
) async {
  final businessRef = FirebaseFirestore.instance
      .collection('businesses')
      .doc(businessId);
  final businessSnap = await businessRef.get();
  final serviceSnap = await businessRef
      .collection('services')
      .where('isActive', isEqualTo: true)
      .get();

  return BusinessCustomerRequestContext(
    businessId: businessId,
    businessExists: businessSnap.exists,
    businessData: businessSnap.data() ?? const {},
    services: serviceSnap.docs
        .map(
          (doc) => BusinessCustomerRequestService(id: doc.id, data: doc.data()),
        )
        .toList(),
  );
}

Stream<List<BusinessCustomerRequestItem>> _watchOpenCustomerRequests() {
  return FirebaseFirestore.instance
      .collection('serviceRequests')
      .where('isActive', isEqualTo: true)
      .where('status', isEqualTo: ServiceRequestMarketplace.statusOpen)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => BusinessCustomerRequestItem(
                id: doc.id,
                data: doc.data(),
                reference: doc.reference,
              ),
            )
            .toList(),
      );
}

Future<void> _updateBusinessCustomerRequestsSetting(
  String businessId,
  bool enabled,
) {
  return FirebaseFirestore.instance
      .collection('businesses')
      .doc(businessId)
      .set({
        'acceptingLeads': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

class BusinessCustomerRequestContext {
  const BusinessCustomerRequestContext({
    required this.businessId,
    required this.businessExists,
    required this.businessData,
    required this.services,
  });

  factory BusinessCustomerRequestContext.missing() {
    return const BusinessCustomerRequestContext(
      businessId: '',
      businessExists: false,
      businessData: {},
      services: [],
    );
  }

  final String businessId;
  final bool businessExists;
  final Map<String, dynamic> businessData;
  final List<BusinessCustomerRequestService> services;

  bool get customerRequestsEnabled => businessData['acceptingLeads'] != false;

  bool get isActive =>
      businessData['isActive'] != false &&
      businessData['status'] != 'inactive' &&
      businessData['isClaimed'] == true;

  bool get hasBusinessLocation => _hasUsableCoordinatePair(
    businessData['latitude'],
    businessData['longitude'],
  );

  BusinessCustomerRequestService? matchingServiceFor(
    Map<String, dynamic> request,
  ) {
    for (final service in services) {
      if (ServiceRequestMarketplace.canCreateOffer(
        request: request,
        business: businessData,
        service: service.data,
        businessId: businessId,
        customerBusinessId: request['customerBusinessId']?.toString(),
        now: DateTime.now(),
      )) {
        return service;
      }
    }
    return null;
  }
}

bool _hasUsableCoordinatePair(Object? latitude, Object? longitude) {
  final lat = latitude is num ? latitude.toDouble() : null;
  final lng = longitude is num ? longitude.toDouble() : null;
  if (lat == null || lng == null) return false;
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  return !(lat.abs() < 0.000001 && lng.abs() < 0.000001);
}

class BusinessCustomerRequestService {
  const BusinessCustomerRequestService({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class BusinessCustomerRequestItem {
  const BusinessCustomerRequestItem({
    required this.id,
    required this.data,
    this.reference,
  });

  final String id;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>>? reference;
}

class _MatchedRequest {
  const _MatchedRequest({required this.item, required this.service});

  final BusinessCustomerRequestItem item;
  final BusinessCustomerRequestService service;
}

class _CustomerRequestsToggleCard extends StatelessWidget {
  const _CustomerRequestsToggleCard({
    required this.enabled,
    required this.updating,
    required this.onChanged,
    this.errorText,
  });

  final bool enabled;
  final bool updating;
  final ValueChanged<bool> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Customer requests',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (updating)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Switch.adaptive(value: enabled, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            enabled
                ? 'Show me relevant requests from people nearby.'
                : 'Turn this on to see relevant requests from people nearby.',
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText!,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

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

class _InlineMessageState extends StatelessWidget {
  const _InlineMessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: AppColors.textMuted),
          const SizedBox(height: 12),
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
            message,
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
