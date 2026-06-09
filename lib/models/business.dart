class BusinessModel {

  final String id;
  final String name;

  final bool isActive;

  final bool chargesEnabled;

  final List<dynamic> paymentMethods;

  final double? latitude;
  final double? longitude;

  final double? distanceMiles;

  final String serviceMode;

  final double serviceRadiusMiles;

  BusinessModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.chargesEnabled,
    required this.paymentMethods,
    this.latitude,
    this.longitude,
    this.distanceMiles,
    required this.serviceMode,
    required this.serviceRadiusMiles,
  });

  factory BusinessModel.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    double? distanceMiles,
  }) {

    return BusinessModel(

      id: id,

      name:
          data['businessName'] ?? '',

      isActive:
          data['isActive'] ?? false,

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

      distanceMiles:
          distanceMiles,

      serviceMode:
          data['serviceMode'] ??
              'premises',

      serviceRadiusMiles:
          (data['serviceRadiusMiles']
                  as num?)
              ?.toDouble() ??
              10,
    );
  }

  bool get canTakeBookings {

    return chargesEnabled ||
        paymentMethods.isNotEmpty;
  }
}