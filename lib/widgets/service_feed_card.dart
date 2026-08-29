import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/booking_screen.dart';
import '../screens/business_detail_screen.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import 'local_link_surface_card.dart';

enum ServiceFeedKind { offer, request }

class ServiceFeedCard extends StatelessWidget {
  final String serviceId;
  final String? businessId;
  final Map<String, dynamic> data;
  final ServiceFeedKind kind;
  final Position? userPosition;

  const ServiceFeedCard({
    super.key,
    required this.serviceId,
    required this.businessId,
    required this.data,
    required this.kind,
    required this.userPosition,
  });

  bool get _isRequest => kind == ServiceFeedKind.request;

  bool get _hasPublishedAvailability {
    final availabilityPostId = data['availabilityPostId']?.toString().trim();
    return availabilityPostId != null && availabilityPostId.isNotEmpty;
  }

  String get _title {
    final directTitle = safeText(data['title'], '');
    if (directTitle.isNotEmpty) return directTitle;

    final serviceName = safeText(data['name'], 'Service');
    return _isRequest ? 'Request a $serviceName' : serviceName;
  }

  String get _details {
    return safeText(
      data['description'] ?? data['details'] ?? data['notes'],
      '',
    );
  }

  double? _milesAway(Map<String, dynamic> locationData) {
    if (userPosition == null) return null;

    final latitude = double.tryParse(
      locationData['latitude']?.toString() ?? '',
    );
    final longitude = double.tryParse(
      locationData['longitude']?.toString() ?? '',
    );

    if (latitude == null || longitude == null) return null;

    return Geolocator.distanceBetween(
          userPosition!.latitude,
          userPosition!.longitude,
          latitude,
          longitude,
        ) /
        1609.34;
  }

  @override
  Widget build(BuildContext context) {
    if (_isRequest || businessId == null || businessId!.isEmpty) {
      return _ServiceCardBody(
        title: _title,
        details: _details,
        kind: kind,
        price: null,
        location: safeText(data['location'] ?? data['address'], ''),
        milesAway: _milesAway(data),
        onTap: null,
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get(),
      builder: (context, snapshot) {
        final businessData =
            snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final businessName = safeText(businessData['businessName'], 'Provider');
        final paymentMethods = resolvePaymentMethods(businessData);

        if (snapshot.hasData) {
          final businessIsActive = businessData['isActive'] != false;
          final businessIsClaimed = businessData['isClaimed'] == true;
          final rawPaymentMethods = businessData['paymentMethods'];
          final canTakeBookings =
              businessData['chargesEnabled'] == true ||
              (rawPaymentMethods is List && rawPaymentMethods.isNotEmpty);

          if (!businessIsActive || !businessIsClaimed || !canTakeBookings) {
            return const SizedBox.shrink();
          }
        }

        final location = safeText(
          businessData['address'] ?? businessData['location'],
          '',
        );

        return _ServiceCardBody(
          title: _title,
          details: _details.isNotEmpty ? _details : businessName,
          kind: kind,
          price: data['price'],
          location: location,
          milesAway: _milesAway(businessData),
          actionLabel: _hasPublishedAvailability
              ? 'Book'
              : 'Enquire with business',
          onTap: snapshot.hasData
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _hasPublishedAvailability
                          ? BookingScreen(
                              businessId: businessId!,
                              businessName: businessName,
                              serviceId: serviceId,
                              serviceData: data,
                              paymentMethods: paymentMethods,
                            )
                          : BusinessDetailScreen(
                              businessId: businessId!,
                              initialServiceId: serviceId,
                            ),
                    ),
                  );
                }
              : null,
        );
      },
    );
  }
}

class _ServiceCardBody extends StatelessWidget {
  final String title;
  final String details;
  final ServiceFeedKind kind;
  final Object? price;
  final String location;
  final double? milesAway;
  final VoidCallback? onTap;
  final String? actionLabel;

  const _ServiceCardBody({
    required this.title,
    required this.details,
    required this.kind,
    required this.price,
    required this.location,
    required this.milesAway,
    required this.onTap,
    this.actionLabel,
  });

  bool get _isRequest => kind == ServiceFeedKind.request;

  String get _label => _isRequest ? 'Requesting Service' : 'Offering Service';

  IconData get _icon =>
      _isRequest ? Icons.campaign_outlined : Icons.handyman_outlined;

  String? get _priceLabel {
    if (_isRequest) return null;
    final value = price;
    if (value is num && value > 0) {
      return formatPrice(value);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: 20,
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.serviceGreen.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(_icon, color: AppColors.serviceGreen, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ServiceBadge(label: _label),
                    if (_priceLabel != null)
                      Text(
                        _priceLabel!,
                        style: const TextStyle(
                          color: AppColors.serviceGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 16,
                    height: 1.18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (location.isNotEmpty)
                      _MetaItem(icon: Icons.place_outlined, label: location),
                    if (milesAway != null)
                      _MetaItem(
                        icon: Icons.near_me_outlined,
                        label: '${milesAway!.toStringAsFixed(1)} miles',
                      ),
                    if (!_isRequest)
                      const _MetaItem(
                        icon: Icons.payment_outlined,
                        label: 'Cash or card',
                      ),
                    if (!_isRequest && actionLabel != null)
                      _MetaItem(
                        icon: Icons.touch_app_outlined,
                        label: actionLabel!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceBadge extends StatelessWidget {
  final String label;

  const _ServiceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.serviceGreen.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.serviceGreen,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.charcoal.withValues(alpha: 0.54)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
