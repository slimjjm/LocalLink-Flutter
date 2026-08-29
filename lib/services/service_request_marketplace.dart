import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceRequestMarketplace {
  const ServiceRequestMarketplace._();

  static const defaultExpiry = Duration(hours: 72);
  static const defaultProviderRadiusMiles = 5.0;

  static const statusOpen = 'open';
  static const statusFilled = 'filled';
  static const statusClosed = 'closed';
  static const statusExpired = 'expired';

  static const offerActive = 'active';
  static const offerWithdrawn = 'withdrawn';
  static const offerAccepted = 'accepted';
  static const offerDeclined = 'declined';

  static DateTime defaultExpiresAt(DateTime now) => now.add(defaultExpiry);

  static DateTime? asDateTime(Object? value) {
    if (value is DateTime) return value;
    try {
      final dynamic timestamp = value;
      final dynamic date = timestamp?.toDate();
      if (date is DateTime) return date;
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool isOpenForDiscovery(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    final status = (data['status'] as String?)?.trim().toLowerCase();
    if (status != null &&
        status.isNotEmpty &&
        status != statusOpen &&
        status != 'discussing') {
      return false;
    }
    if (data['isActive'] == false) return false;

    final expiresAt = asDateTime(data['expiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(now)) return false;

    return true;
  }

  static bool canCreateOffer({
    required Map<String, dynamic> request,
    required Map<String, dynamic> business,
    required Map<String, dynamic> service,
    required String businessId,
    required String? customerBusinessId,
    required DateTime now,
    double maxRadiusMiles = defaultProviderRadiusMiles,
  }) {
    if (!isOpenForDiscovery(request, now: now)) return false;
    if (customerBusinessId != null &&
        customerBusinessId.isNotEmpty &&
        customerBusinessId == businessId) {
      return false;
    }
    if (!isBusinessEligible(business)) return false;
    if (!isServiceMatchingRequest(request: request, service: service)) {
      return false;
    }

    final distance = distanceMiles(
      request['approxLatitude'],
      request['approxLongitude'],
      business['latitude'],
      business['longitude'],
    );
    if (distance == null) return true;
    final radius =
        (business['leadRadiusMiles'] as num?)?.toDouble() ??
        (business['serviceRadiusMiles'] as num?)?.toDouble() ??
        maxRadiusMiles;
    return distance <= math.max(radius, maxRadiusMiles);
  }

  static bool isBusinessEligible(Map<String, dynamic> business) {
    return business['isActive'] != false &&
        business['isClaimed'] == true &&
        business['acceptingLeads'] != false;
  }

  static bool isServiceMatchingRequest({
    required Map<String, dynamic> request,
    required Map<String, dynamic> service,
  }) {
    if (service['isActive'] == false ||
        service['isPublished'] == false ||
        service['isEnabled'] == false) {
      return false;
    }

    final category = _normalise(request['category']);
    if (category.isEmpty) return true;

    final serviceText = [
      service['category'],
      service['name'],
      service['serviceName'],
      service['details'],
      service['description'],
      service['searchKeywords'],
    ].map(_normalise).join(' ');

    return serviceText.contains(category) || category.contains(serviceText);
  }

  static double? distanceMiles(
    Object? aLat,
    Object? aLng,
    Object? bLat,
    Object? bLng,
  ) {
    final lat1 = (aLat as num?)?.toDouble();
    final lng1 = (aLng as num?)?.toDouble();
    final lat2 = (bLat as num?)?.toDouble();
    final lng2 = (bLng as num?)?.toDouble();
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return null;
    }

    const earthRadiusMiles = 3958.8;
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMiles * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static String publicLocation(Map<String, dynamic> data) {
    return (data['publicLocation'] ??
            data['location'] ??
            data['town'] ??
            data['city'] ??
            '')
        .toString()
        .trim();
  }

  static String _normalise(Object? value) {
    if (value is Iterable) {
      return value.map(_normalise).where((v) => v.isNotEmpty).join(' ');
    }
    return (value ?? '').toString().trim().toLowerCase().replaceAll(
      RegExp('[^a-z0-9]+'),
      ' ',
    );
  }

  static double _radians(double value) => value * math.pi / 180;
}

class ServiceRequestCommands {
  ServiceRequestCommands({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get requests =>
      _firestore.collection('serviceRequests');

  Future<DocumentReference<Map<String, dynamic>>> createRequest({
    required String customerId,
    required String category,
    required String title,
    required String description,
    required String scheduleText,
    required String publicLocation,
    required double approxLatitude,
    required double approxLongitude,
    String? budgetText,
  }) {
    final now = DateTime.now();
    return requests.add({
      'customerId': customerId,
      'category': category,
      'title': title,
      'description': description,
      'scheduleText': scheduleText,
      if (budgetText != null && budgetText.trim().isNotEmpty)
        'budgetText': budgetText.trim(),
      'publicLocation': publicLocation,
      'location': publicLocation,
      'locationPrecision': 'approximate',
      'approxLatitude': approxLatitude,
      'approxLongitude': approxLongitude,
      'status': ServiceRequestMarketplace.statusOpen,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        ServiceRequestMarketplace.defaultExpiresAt(now),
      ),
    });
  }

  Future<void> closeRequest(String requestId, {required String status}) {
    return requests.doc(requestId).set({
      'status': status,
      'isActive': false,
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> renewRequest(String requestId) {
    return requests.doc(requestId).set({
      'status': ServiceRequestMarketplace.statusOpen,
      'isActive': true,
      'closedAt': FieldValue.delete(),
      'expiresAt': Timestamp.fromDate(
        ServiceRequestMarketplace.defaultExpiresAt(DateTime.now()),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> upsertOffer({
    required String requestId,
    required String businessId,
    required String businessName,
    required String serviceId,
    required String serviceName,
    String? priceText,
    String? message,
  }) async {
    final offerRef = requests
        .doc(requestId)
        .collection('offers')
        .doc(businessId);
    final existing = await offerRef.get();
    final data = {
      'businessId': businessId,
      'businessName': businessName,
      'serviceId': serviceId,
      'serviceName': serviceName,
      if (priceText != null && priceText.trim().isNotEmpty)
        'priceText': priceText.trim(),
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      'status': ServiceRequestMarketplace.offerActive,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    };

    if (existing.exists) {
      await offerRef.update(data);
    } else {
      await offerRef.set(data);
    }
  }

  Future<void> withdrawOffer({
    required String requestId,
    required String businessId,
  }) {
    return requests.doc(requestId).collection('offers').doc(businessId).set({
      'status': ServiceRequestMarketplace.offerWithdrawn,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> acceptOffer({
    required String requestId,
    required String businessId,
  }) async {
    final requestRef = requests.doc(requestId);
    final offerRef = requestRef.collection('offers').doc(businessId);
    await _firestore.runTransaction((transaction) async {
      transaction.set(offerRef, {
        'status': ServiceRequestMarketplace.offerAccepted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(requestRef, {
        'status': ServiceRequestMarketplace.statusFilled,
        'isActive': false,
        'closedAt': FieldValue.serverTimestamp(),
        'acceptedBusinessId': businessId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
