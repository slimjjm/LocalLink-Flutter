import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/service_request_marketplace.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';

class BusinessServiceRequestsScreen extends StatelessWidget {
  const BusinessServiceRequestsScreen({super.key, this.businessId});

  final String? businessId;

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
      body: businessId == null || businessId!.isEmpty
          ? const _MessageState(
              icon: Icons.storefront_outlined,
              title: 'Choose a business first',
              message: 'Requests are matched to your active business services.',
            )
          : _MatchedRequestList(businessId: businessId!),
    );
  }
}

class _MatchedRequestList extends StatelessWidget {
  const _MatchedRequestList({required this.businessId});

  final String businessId;

  Future<_BusinessOfferContext> _loadContext() async {
    final businessRef = FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId);
    final businessSnap = await businessRef.get();
    final serviceSnap = await businessRef
        .collection('services')
        .where('isActive', isEqualTo: true)
        .get();

    return _BusinessOfferContext(
      business: businessSnap,
      services: serviceSnap.docs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BusinessOfferContext>(
      future: _loadContext(),
      builder: (context, contextSnapshot) {
        if (!contextSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final offerContext = contextSnapshot.data!;
        if (!offerContext.business.exists ||
            !ServiceRequestMarketplace.isBusinessEligible(
              offerContext.business.data() ?? const {},
            )) {
          return const _MessageState(
            icon: Icons.pause_circle_outline,
            title: 'Leads are paused',
            message:
                'Turn on leads and keep your business active to see matching requests.',
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('serviceRequests')
              .where('isActive', isEqualTo: true)
              .where('status', isEqualTo: ServiceRequestMarketplace.statusOpen)
              .orderBy('createdAt', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              assert(() {
                debugPrint(
                  'serviceRequests provider query failed: ${snapshot.error}',
                );
                return true;
              }());
              return const _MessageState(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load requests',
                message: 'Please try again in a moment.',
              );
            }

            final now = DateTime.now();
            final docs = (snapshot.data?.docs ?? const [])
                .map((doc) {
                  final service = offerContext.matchingServiceFor(doc.data());
                  if (service == null) return null;
                  return _MatchedRequest(doc: doc, service: service);
                })
                .whereType<_MatchedRequest>()
                .where(
                  (match) => ServiceRequestMarketplace.isOpenForDiscovery(
                    match.doc.data(),
                    now: now,
                  ),
                )
                .toList();

            if (docs.isEmpty) {
              return const _MessageState(
                icon: Icons.search_off_rounded,
                title: 'No matching requests right now',
                message:
                    'Customer requests that match your active services will appear here.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: docs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final match = docs[index];
                return _ProviderRequestCard(
                  businessId: businessId,
                  businessData: offerContext.business.data() ?? const {},
                  request: match.doc,
                  service: match.service,
                );
              },
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
  final QueryDocumentSnapshot<Map<String, dynamic>> request;
  final QueryDocumentSnapshot<Map<String, dynamic>> service;

  Future<void> _showOfferSheet(BuildContext context) async {
    final existing = await request.reference
        .collection('offers')
        .doc(businessId)
        .get();
    if (!context.mounted) return;

    final data = existing.data() ?? const {};
    final priceController = TextEditingController(
      text: safeText(data['priceText'], ''),
    );
    final messageController = TextEditingController(
      text: safeText(data['message'], ''),
    );

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
          serviceName: safeText(service.data()['name'], 'Service'),
          priceText: priceController.text,
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
      messageController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = request.data();
    final title = safeText(data['title'], 'Request for help');
    final details = safeText(data['description'] ?? data['details'], '');
    final location = ServiceRequestMarketplace.publicLocation(data);
    final schedule = safeText(data['scheduleText'] ?? data['neededBy'], '');
    final budget = safeText(data['budgetText'] ?? data['budget'], '');
    final distance = ServiceRequestMarketplace.distanceMiles(
      data['approxLatitude'],
      data['approxLongitude'],
      businessData['latitude'],
      businessData['longitude'],
    );

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: request.reference
          .collection('offers')
          .doc(businessId)
          .snapshots(),
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

class _BusinessOfferContext {
  const _BusinessOfferContext({required this.business, required this.services});

  final DocumentSnapshot<Map<String, dynamic>> business;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> services;

  QueryDocumentSnapshot<Map<String, dynamic>>? matchingServiceFor(
    Map<String, dynamic> request,
  ) {
    final businessData = business.data() ?? const {};
    for (final service in services) {
      if (ServiceRequestMarketplace.canCreateOffer(
        request: request,
        business: businessData,
        service: service.data(),
        businessId: business.id,
        customerBusinessId: request['customerBusinessId']?.toString(),
        now: DateTime.now(),
      )) {
        return service;
      }
    }
    return null;
  }
}

class _MatchedRequest {
  const _MatchedRequest({required this.doc, required this.service});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final QueryDocumentSnapshot<Map<String, dynamic>> service;
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
