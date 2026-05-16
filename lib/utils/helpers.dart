import 'package:cloud_firestore/cloud_firestore.dart';

String safeText(dynamic value, String fallback) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String formatPrice(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  return '£${number.toStringAsFixed(number.truncateToDouble() == number ? 0 : 2)}';
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

List<String> resolvePaymentMethods(Map<String, dynamic> businessData) {
  final paymentMethods = businessData['paymentMethods'];

  if (paymentMethods is List) {
    return paymentMethods.map((e) => e.toString()).toList();
  }

  final paymentMethod = businessData['paymentMethod'];

  if (paymentMethod is String && paymentMethod.trim().isNotEmpty) {
    return [paymentMethod.trim()];
  }

  return ['cash'];
}