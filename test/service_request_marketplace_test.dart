import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/service_request_marketplace.dart';

void main() {
  final now = DateTime(2026, 8, 28, 10);

  Map<String, dynamic> request({
    String status = ServiceRequestMarketplace.statusOpen,
    bool isActive = true,
    DateTime? expiresAt,
    String category = 'Cleaner',
    double lat = 52.68,
    double lng = -1.83,
  }) {
    return {
      'status': status,
      'isActive': isActive,
      'expiresAt': expiresAt ?? now.add(const Duration(hours: 1)),
      'category': category,
      'publicLocation': 'Burntwood',
      'approxLatitude': lat,
      'approxLongitude': lng,
    };
  }

  Map<String, dynamic> business({
    bool isActive = true,
    bool isClaimed = true,
    bool acceptingLeads = true,
    double lat = 52.681,
    double lng = -1.831,
    List<String> paymentMethods = const ['cash'],
  }) {
    return {
      'isActive': isActive,
      'isClaimed': isClaimed,
      'acceptingLeads': acceptingLeads,
      'latitude': lat,
      'longitude': lng,
      'paymentMethods': paymentMethods,
    };
  }

  Map<String, dynamic> service({
    bool isActive = true,
    String category = 'Cleaner',
    String name = 'Home cleaning',
  }) {
    return {
      'isActive': isActive,
      'category': category,
      'name': name,
      'details': 'Weekly house cleans',
    };
  }

  test('new service requests default to 72 hours', () {
    expect(
      ServiceRequestMarketplace.defaultExpiresAt(now),
      now.add(const Duration(hours: 72)),
    );
  });

  test('open requests are discoverable until expiry', () {
    expect(
      ServiceRequestMarketplace.isOpenForDiscovery(request(), now: now),
      isTrue,
    );
  });

  test('closed and filled requests are not discoverable', () {
    expect(
      ServiceRequestMarketplace.isOpenForDiscovery(
        request(status: ServiceRequestMarketplace.statusClosed),
        now: now,
      ),
      isFalse,
    );
    expect(
      ServiceRequestMarketplace.isOpenForDiscovery(
        request(status: ServiceRequestMarketplace.statusFilled),
        now: now,
      ),
      isFalse,
    );
  });

  test('expired requests are not discoverable', () {
    expect(
      ServiceRequestMarketplace.isOpenForDiscovery(
        request(expiresAt: now.subtract(const Duration(minutes: 1))),
        now: now,
      ),
      isFalse,
    );
  });

  test('cash-only active claimed businesses can offer', () {
    expect(
      ServiceRequestMarketplace.canCreateOffer(
        request: request(),
        business: business(paymentMethods: const ['cash']),
        service: service(),
        businessId: 'business-1',
        customerBusinessId: null,
        now: now,
      ),
      isTrue,
    );
  });

  test('inactive, unclaimed or paused businesses cannot offer', () {
    for (final candidate in [
      business(isActive: false),
      business(isClaimed: false),
      business(acceptingLeads: false),
    ]) {
      expect(
        ServiceRequestMarketplace.canCreateOffer(
          request: request(),
          business: candidate,
          service: service(),
          businessId: 'business-1',
          customerBusinessId: null,
          now: now,
        ),
        isFalse,
      );
    }
  });

  test('inactive and non-matching services cannot offer', () {
    expect(
      ServiceRequestMarketplace.canCreateOffer(
        request: request(),
        business: business(),
        service: service(isActive: false),
        businessId: 'business-1',
        customerBusinessId: null,
        now: now,
      ),
      isFalse,
    );
    expect(
      ServiceRequestMarketplace.canCreateOffer(
        request: request(category: 'Cleaner'),
        business: business(),
        service: service(category: 'Gardener', name: 'Garden tidy'),
        businessId: 'business-1',
        customerBusinessId: null,
        now: now,
      ),
      isFalse,
    );
  });

  test('customer own business cannot offer', () {
    expect(
      ServiceRequestMarketplace.canCreateOffer(
        request: request(),
        business: business(),
        service: service(),
        businessId: 'business-1',
        customerBusinessId: 'business-1',
        now: now,
      ),
      isFalse,
    );
  });

  test('business outside the initial request radius cannot offer', () {
    expect(
      ServiceRequestMarketplace.canCreateOffer(
        request: request(),
        business: business(lat: 53.4, lng: -2.2),
        service: service(),
        businessId: 'business-1',
        customerBusinessId: null,
        now: now,
      ),
      isFalse,
    );
  });

  test('public location never falls back to precise coordinate fields', () {
    expect(
      ServiceRequestMarketplace.publicLocation({
        'publicLocation': 'Burntwood',
        'latitude': 52.681234,
        'longitude': -1.831234,
      }),
      'Burntwood',
    );
  });
}
