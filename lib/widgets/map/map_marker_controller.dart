import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'locallink_marker.dart';

class MapMarkerController {
  final Map<String, BitmapDescriptor> _iconCache = {};

  Future<Set<Marker>> buildMarkers({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String? selectedOpportunityId,
    required LatLng? Function(Map<String, dynamic>) latLngFromData,
    required ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onMarkerTap,
  }) async {
    final markers = <Marker>{};

    for (final doc in docs) {
      final data = doc.data();

      final latLng = latLngFromData(data);
      if (latLng == null) continue;

      final category = data['category']?.toString() ?? 'Local';
      final attendees = (data['attendeeCount'] as num?)?.toInt() ?? 0;
      final selected = doc.id == selectedOpportunityId;

      final cacheKey =
          '$category|$attendees|$selected';

      BitmapDescriptor icon;

      if (_iconCache.containsKey(cacheKey)) {
        icon = _iconCache[cacheKey]!;
      } else {
        icon = await LocalLinkMarker.build(
          category: category,
          attendeeCount: attendees,
          selected: selected,
        );

        _iconCache[cacheKey] = icon;
      }

      markers.add(
        Marker(
          markerId: MarkerId(doc.id),
          position: latLng,
          icon: icon,
          zIndex: selected ? 100 : 1,
          infoWindow: InfoWindow.noText,
          onTap: () => onMarkerTap(doc),
        ),
      );
    }

    return markers;
  }

  void clear() {
    _iconCache.clear();
  }
}