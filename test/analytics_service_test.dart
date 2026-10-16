import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/analytics_service.dart';

void main() {
  test('analytics service no-ops before Firebase is initialized', () async {
    final analytics = LocalLinkAnalytics.instance;

    await analytics.updateUserProperties();
    await analytics.askLocalLinkSearch(intentType: 'service', resultCount: 2);
    await analytics.askLocalLinkResultOpened(
      resultType: 'business',
      resultPosition: 1,
      intentType: 'service',
    );
    await analytics.bookingStarted(
      source: 'business_detail',
      paymentMethod: 'stripe',
    );
    await analytics.bookingCompleted(
      source: 'business_detail',
      paymentMethod: 'stripe',
    );
    await analytics.bookingCancelled(source: 'customer_booking_detail');
  });
}
