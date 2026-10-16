import 'business_discovery_service.dart';

/// Conservative guidance: unknown categories never receive automatic nudges.
class BusinessActivationPolicy {
  static const appointmentCategories = {
    'aesthetics',
    'beauty',
    'brows & lashes',
    'hair salon',
    'barber',
    'nails',
    'massage',
    'skin clinic',
    'dog groomer',
    'dog walker',
    'mobile valeting',
    'personal trainer',
  };
  static const enquiryCategories = {
    'cleaner',
    'gardener',
    'handyman',
    'pressure washing',
    'specialist services',
    'plumber',
    'electrician',
    'builder',
    'tradesperson',
  };

  static bool suggestsServices(String category) =>
      appointmentCategories.contains(category.trim().toLowerCase());

  static bool hasClaimedOwner(Map<String, dynamic> data) =>
      (data['ownerId']?.toString().trim() ?? '').isNotEmpty &&
      (data['isClaimed'] == true ||
          data['listingOwnershipStatus'] == 'claimed' ||
          data['claimStatus'] == 'approved');

  static bool listingLive(Map<String, dynamic> data) =>
      BusinessDiscoveryService.isPubliclyDiscoverable(data);

  /// Only existing public contact fields, never a moderator's profile details.
  static Map<String, Uri> contactLinks(Map<String, dynamic> data) {
    if (!listingLive(data) || !hasClaimedOwner(data)) return {};
    final links = <String, Uri>{};
    final phone = (data['phone'] ?? '').toString().trim();
    final dialNumber = phone
        .replaceFirst(RegExp(r'^\+44\s*\(0\)'), '+44')
        .replaceAll(RegExp(r'[ ()-]'), '');
    if (RegExp(r'^\+?[0-9 ()-]{6,24}$').hasMatch(phone) &&
        RegExp(r'^\+?[0-9]{7,15}$').hasMatch(dialNumber)) {
      links['Call business'] = Uri(scheme: 'tel', path: dialNumber);
    }
    final email = (data['email'] ?? '').toString().trim();
    if (RegExp(r'^[^\s@?&#]+@[^\s@?&#]+\.[^\s@?&#]+$').hasMatch(email)) {
      links['Email business'] = Uri(scheme: 'mailto', path: email);
    }
    final website = Uri.tryParse((data['website'] ?? '').toString().trim());
    if (website != null &&
        {'http', 'https'}.contains(website.scheme) &&
        website.host.isNotEmpty &&
        website.userInfo.isEmpty) {
      links['Visit website'] = website;
    }
    return links;
  }

  /// Readiness is a snapshot of an existing booking route, not a reservation.
  /// Direct availability can be booked without staff; calendar slots require a
  /// staff member assigned to an active service and enough contiguous time.
  static bool hasBookingOptions({
    required List<Map<String, dynamic>> services,
    required List<Map<String, dynamic>> staff,
    required List<Map<String, dynamic>> slots,
    required List<Map<String, dynamic>> posts,
    required DateTime now,
  }) {
    DateTime? date(Object? value) {
      if (value is DateTime) return value;
      try {
        return (value as dynamic)?.toDate() as DateTime?;
      } catch (_) {
        return null;
      }
    }

    final liveServices = {
      for (final service in services)
        if (service['isActive'] == true &&
            service['price'] is num &&
            (service['price'] as num) > 0)
          service['id'].toString(): service,
    };
    for (final post in posts) {
      final end = date(
        post['endTime'] ??
            post['endDateTime'] ??
            post['availableUntil'] ??
            post['startDateTime'] ??
            post['startTime'] ??
            post['availabilityAt'],
      );
      if (post['isActive'] == true &&
          post['status'] == 'live' &&
          liveServices.containsKey(post['serviceId']) &&
          end != null &&
          end.isAfter(now)) {
        return true;
      }
    }
    for (final person in staff.where((person) => person['isActive'] == true)) {
      final ids = person['serviceIds'];
      if (ids is! List) continue;
      final durations = ids
          .where(liveServices.containsKey)
          .map(
            (id) =>
                (liveServices[id]!['durationMinutes'] as num?)?.toInt() ?? 30,
          )
          .where((minutes) => minutes > 0);
      if (durations.isEmpty) continue;
      final requiredMinutes = durations.reduce((a, b) => a < b ? a : b);
      final available =
          slots.where((slot) {
            final start = date(slot['startTime']);
            final end = date(slot['endTime']);
            final lock = date(slot['lockExpiresAt']);
            return slot['staffId'] == person['id'] &&
                slot['isBooked'] == false &&
                start != null &&
                start.isAfter(now) &&
                end != null &&
                end.isAfter(start) &&
                (lock == null || !lock.isAfter(now));
          }).toList()..sort(
            (a, b) => date(a['startTime'])!.compareTo(date(b['startTime'])!),
          );
      DateTime? blockStart;
      DateTime? blockEnd;
      for (final slot in available) {
        final start = date(slot['startTime'])!;
        final end = date(slot['endTime'])!;
        if (blockEnd == null || start.isAfter(blockEnd)) {
          blockStart = start;
          blockEnd = end;
        } else if (end.isAfter(blockEnd)) {
          blockEnd = end;
        }
        if (blockEnd.difference(blockStart!).inMinutes >= requiredMinutes) {
          return true;
        }
      }
    }
    return false;
  }

  static String firstStep(String category) {
    final value = category.trim().toLowerCase();
    if (appointmentCategories.contains(value)) {
      return 'Add your first service so people can ask about what you offer. You can share appointment times when you are ready.';
    }
    if (enquiryCategories.contains(value)) {
      return 'Keep your contact details up to date so people can ask for a quote. You can also add a service to explain what you offer.';
    }
    return 'Keep your contact details and opening hours up to date. Add services only if customers would find them useful.';
  }
}
