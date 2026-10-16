import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

String safeText(dynamic value, String fallback) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String safeInitial(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return '?';
  return String.fromCharCode(text.runes.first).toUpperCase();
}

String formatPrice(dynamic value) {
  if (value == null) {
    return 'Price on request';
  }

  final pence = value is num ? value.toDouble() : double.tryParse('$value');

  if (pence == null || pence <= 0) {
    return 'Price on request';
  }

  final pounds = pence / 100;

  return '£${pounds.toStringAsFixed(2)}';
}

String businessCoverImageUrl(Map<String, dynamic> businessData) {
  for (final value in [
    businessData['coverPhoto'],
    businessData['bannerImageUrl'],
    businessData['bannerUrl'],
  ]) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }

  for (final key in ['photoURLs', 'galleryUrls']) {
    final value = businessData[key];
    if (value is Iterable) {
      for (final item in value) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
    }
  }

  final imageUrl = businessData['imageUrl']?.toString().trim() ?? '';
  if (imageUrl.isNotEmpty) return imageUrl;

  return '';
}

List<String> businessPhotoUrls(Map<String, dynamic> businessData) {
  final urls = <String>[];
  for (final key in ['photoURLs', 'galleryUrls']) {
    final value = businessData[key];
    if (value is Iterable) {
      for (final item in value) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) urls.add(text);
      }
    }
  }
  return urls;
}

String formatSlotTime(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
  return 'Unknown time';
}

DateTime? dateTimeFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String formatFreshnessLabel({required dynamic createdAt, dynamic updatedAt}) {
  final created = dateTimeFromValue(createdAt);
  final updated = dateTimeFromValue(updatedAt);
  final useUpdated =
      updated != null &&
      created != null &&
      updated.difference(created).inMinutes > 2;
  final date = useUpdated ? updated : created;

  if (date == null) return 'Recently added';

  final now = DateTime.now();
  final difference = now.difference(date);
  final prefix = useUpdated ? 'Updated' : 'Posted';

  if (difference.inMinutes < 1) return '$prefix just now';
  if (difference.inMinutes < 60) {
    return '$prefix ${difference.inMinutes} minutes ago';
  }
  if (difference.inHours < 24) {
    return '$prefix ${difference.inHours} hours ago';
  }
  if (difference.inDays == 1) return '$prefix yesterday';
  if (difference.inDays < 7) return '$prefix ${difference.inDays} days ago';

  return '$prefix ${date.day}/${date.month}/${date.year}';
}

List<String> resolvePaymentMethods(Map<String, dynamic> businessData) {
  bool stripeReady() {
    return businessData['stripeConnected'] == true &&
        businessData['stripeChargesEnabled'] == true;
  }

  List<String> filterMethods(Iterable methods) {
    final resolved = <String>[];

    for (final method in methods) {
      final normalised = method.toString().trim().toLowerCase();
      if (normalised.isEmpty || resolved.contains(normalised)) continue;
      if (normalised == 'stripe' && !stripeReady()) continue;
      resolved.add(normalised);
    }

    return resolved;
  }

  final paymentMethods = businessData['paymentMethods'];

  if (paymentMethods is List) {
    return filterMethods(paymentMethods);
  }

  final paymentMethod = businessData['paymentMethod'];

  if (paymentMethod is String && paymentMethod.trim().isNotEmpty) {
    return filterMethods([paymentMethod]);
  }

  return [];
}

String paymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'stripe':
      return 'Card & Apple Pay';
    case 'bank_transfer':
      return 'Bank transfer';
    case 'cash':
      return 'Cash';
    default:
      return method.trim().isEmpty ? 'Payment to be arranged' : method.trim();
  }
}

IconData paymentMethodIcon(String method) {
  switch (method.trim().toLowerCase()) {
    case 'stripe':
      return Icons.credit_card_outlined;
    case 'bank_transfer':
      return Icons.account_balance_outlined;
    case 'cash':
      return Icons.payments_outlined;
    default:
      return Icons.payment_outlined;
  }
}
