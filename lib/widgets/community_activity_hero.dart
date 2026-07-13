import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../screens/opportunity_map_screen.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';

class CommunityActivityHero extends StatelessWidget {
  const CommunityActivityHero({super.key});

  static const LatLng _defaultCenter = LatLng(52.6816, -1.8260);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Position?>(
      future: LocationService().getCurrentLocation(),
      builder: (context, locationSnapshot) {
        final userPosition = locationSnapshot.data;

        return FutureBuilder<String>(
          future: _locationLabel(userPosition),
          builder: (context, placeSnapshot) {
            final placeLabel =
                placeSnapshot.data ??
                (userPosition == null ? 'Local map' : 'Near you');

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('opportunities')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                final opportunities = (snapshot.data?.docs ?? [])
                    .map(
                      (doc) => _OpportunityLocation(
                        id: doc.id,
                        data: doc.data() as Map<String, dynamic>,
                      ),
                    )
                    .where((opportunity) {
                      return _isCurrentOpportunity(opportunity.data) &&
                          _latLngFromData(opportunity.data) != null;
                    })
                    .take(28)
                    .toList();

                final markers = opportunities
                    .map(
                      (opportunity) => Marker(
                        markerId: MarkerId(opportunity.id),
                        position: _latLngFromData(opportunity.data)!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          _categoryHue(
                            opportunity.data['category']?.toString() ?? '',
                          ),
                        ),
                        onTap: () => _openMap(context),
                      ),
                    )
                    .toSet();

                final center = userPosition == null
                    ? _centerFromMarkers(markers)
                    : LatLng(userPosition.latitude, userPosition.longitude);

                return Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openMap(context),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.70),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Explore Nearby',
                                        style: TextStyle(
                                          color: AppColors.charcoal,
                                          fontSize: 22,
                                          height: 1.08,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Open the map to discover what is close by.',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                          height: 1.34,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _MapLabel(
                                  icon: userPosition == null
                                      ? Icons.explore_outlined
                                      : Icons.near_me_outlined,
                                  label: placeLabel,
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: AspectRatio(
                              aspectRatio: 1.78,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target: center,
                                          zoom: userPosition == null
                                              ? 12.4
                                              : 13.8,
                                        ),
                                        markers: markers,
                                        myLocationEnabled: userPosition != null,
                                        myLocationButtonEnabled: false,
                                        zoomControlsEnabled: false,
                                        mapToolbarEnabled: false,
                                        compassEnabled: false,
                                        rotateGesturesEnabled: false,
                                        scrollGesturesEnabled: false,
                                        tiltGesturesEnabled: false,
                                        zoomGesturesEnabled: false,
                                        liteModeEnabled: true,
                                        onTap: (_) => _openMap(context),
                                      ),
                                    ),
                                    const Positioned(
                                      right: 14,
                                      bottom: 14,
                                      child: _MapHint(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _openMap(context),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Explore on Map'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.charcoal,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OpportunityMapScreen()),
    );
  }

  static Future<String> _locationLabel(Position? position) async {
    if (position == null) {
      return 'Local map';
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        return 'Near you';
      }

      final place = placemarks.first;
      final name =
          [
                place.locality,
                place.subLocality,
                place.subAdministrativeArea,
                place.administrativeArea,
              ]
              .whereType<String>()
              .map((value) => value.trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => '');

      if (name.isEmpty) {
        return 'Near you';
      }

      return 'Near $name';
    } catch (_) {
      return 'Near you';
    }
  }

  static bool _isCurrentOpportunity(Map<String, dynamic> data) {
    final eventDate = data['eventDate'];

    if (eventDate is Timestamp) {
      return !eventDate.toDate().isBefore(DateTime.now());
    }

    return true;
  }

  static LatLng? _latLngFromData(Map<String, dynamic> data) {
    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');

    if (lat == null || lng == null) {
      return null;
    }

    return LatLng(lat, lng);
  }

  static LatLng _centerFromMarkers(Set<Marker> markers) {
    if (markers.isEmpty) {
      return _defaultCenter;
    }

    var lat = 0.0;
    var lng = 0.0;

    for (final marker in markers) {
      lat += marker.position.latitude;
      lng += marker.position.longitude;
    }

    return LatLng(lat / markers.length, lng / markers.length);
  }

  static double _categoryHue(String category) {
    switch (category) {
      case 'Fitness & Sport':
        return BitmapDescriptor.hueGreen;
      case 'Family':
        return BitmapDescriptor.hueRose;
      case 'Pets':
        return BitmapDescriptor.hueOrange;
      case 'Hobbies':
        return BitmapDescriptor.hueViolet;
      case 'Social':
        return BitmapDescriptor.hueAzure;
      case 'Volunteering':
        return BitmapDescriptor.hueRed;
      case 'Learning':
        return BitmapDescriptor.hueCyan;
      case 'Local Deals':
        return BitmapDescriptor.hueBlue;
      default:
        return BitmapDescriptor.hueOrange;
    }
  }
}

class _OpportunityLocation {
  final String id;
  final Map<String, dynamic> data;

  const _OpportunityLocation({required this.id, required this.data});
}

class _MapLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MapLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 138),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.62)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.charcoal),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapHint extends StatelessWidget {
  const _MapHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.62)),
      ),
      child: const Icon(
        Icons.open_in_full_rounded,
        color: AppColors.charcoal,
        size: 17,
      ),
    );
  }
}
