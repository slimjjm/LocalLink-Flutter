class BusinessModel {

  final String id;
  final String name;

  final bool isActive;

  final bool chargesEnabled;

  final List<dynamic> paymentMethods;

  final double? latitude;
  final double? longitude;

  BusinessModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.chargesEnabled,
    required this.paymentMethods,
    this.latitude,
    this.longitude,
  });

  factory BusinessModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {

    return BusinessModel(

      id: id,

      name: data['businessName'] ?? '',

      isActive: data['isActive'] ?? false,

      chargesEnabled:
          data['chargesEnabled'] ?? false,

      paymentMethods:
          data['paymentMethods'] ?? [],

      latitude:
          (data['latitude'] as num?)
              ?.toDouble(),

      longitude:
          (data['longitude'] as num?)
              ?.toDouble(),
    );
  }

  bool get canTakeBookings {

    return chargesEnabled ||
        paymentMethods.isNotEmpty;
  }
}