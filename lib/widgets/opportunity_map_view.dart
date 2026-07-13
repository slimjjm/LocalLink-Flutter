import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../screens/opportunity_detail_screen.dart';
import '../theme/app_colors.dart';

import 'map/map_marker_controller.dart';


class OpportunityMapView extends StatefulWidget {
  const OpportunityMapView({super.key});

  @override
  State<OpportunityMapView> createState() => _OpportunityMapViewState();
}

class _OpportunityMapViewState extends State<OpportunityMapView> {
  GoogleMapController? _mapController;

  final MapMarkerController _markerController =
    MapMarkerController();

Set<Marker> _markers = {};


  String? _selectedOpportunityId;
  bool _showSearchThisArea = false;

  static const LatLng _defaultCenter = LatLng(
    52.6816,
    -1.8260,
  );

  Stream<QuerySnapshot<Map<String, dynamic>>> get _opportunityStream {
    return FirebaseFirestore.instance
        .collection('opportunities')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

@override
void dispose() {
  _markerController.clear();
  _mapController?.dispose();
  super.dispose();
}

  double? _readDouble(
    Map<String, dynamic> data,
    String key,
  ) {
    final value = data[key];
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  LatLng? _latLngFromData(
    Map<String, dynamic> data,
  ) {
    final latitude = _readDouble(data, 'latitude');
    final longitude = _readDouble(data, 'longitude');

    if (latitude == null || longitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  bool _isFutureOpportunity(
    Map<String, dynamic> data,
  ) {
    final eventDate = data['eventDate'];

    if (eventDate is Timestamp) {
      return eventDate.toDate().isAfter(DateTime.now());
    }

    return true;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mappableDocs(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.where((doc) {
      final data = doc.data();

      return _latLngFromData(data) != null &&
          _isFutureOpportunity(data);
    }).toList();
  }

  BitmapDescriptor _markerIcon({
    required bool selected,
  }) {
    return BitmapDescriptor.defaultMarkerWithHue(
      selected
          ? BitmapDescriptor.hueOrange
          : BitmapDescriptor.hueRed,
    );
  }


Future<void> _refreshMarkers(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) async {
  final markers =
      await _markerController.buildMarkers(
    docs: docs,
    selectedOpportunityId:
        _selectedOpportunityId,
    latLngFromData: _latLngFromData,
    onMarkerTap: (doc) {
      _selectOpportunity(
        doc,
        animateCamera: true,
      );
    },
  );

  if (!mounted) return;

  setState(() {
    _markers = markers;
  });
}
  Future<void> _selectOpportunity(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool animateCamera,
  }) async {
    final latLng = _latLngFromData(doc.data());

    setState(() {
      _selectedOpportunityId = doc.id;
    });

    if (animateCamera && latLng != null) {
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 14.5,
          ),
        ),
      );
    }
  }

  Future<void> _searchThisArea() async {
    setState(() {
      _showSearchThisArea = false;
    });

    // Proper visible-bounds Firestore filtering comes in the next pass.
    await _mapController?.getVisibleRegion();
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _selectedDocFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_selectedOpportunityId == null) {
      return null;
    }

    for (final doc in docs) {
      if (doc.id == _selectedOpportunityId) {
        return doc;
      }
    }

    return null;
  }

  String _mapStyle() {
    return '''
[
  {
    "featureType": "poi.business",
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "transit",
    "stylers": [
      { "visibility": "off" }
    ]
  }
]
''';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _opportunityStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _MapMessage(
            icon: Icons.error_outline_rounded,
            title: 'Map could not load',
            message: 'Something went wrong loading nearby opportunities.',
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final docs = _mappableDocs(snapshot.data!);
     if (_markers.length != docs.length) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _refreshMarkers(docs);
 });
}
        final selectedDoc = _selectedDocFrom(docs);

        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _defaultCenter,
                zoom: 13,
              ),
             markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              buildingsEnabled: true,
              trafficEnabled: false,
              indoorViewEnabled: false,
              onMapCreated: (controller) async {
                _mapController = controller;
                await controller.setMapStyle(_mapStyle());
              },
              onCameraMove: (_) {
                if (!_showSearchThisArea) {
                  setState(() {
                    _showSearchThisArea = true;
                  });
                }
              },
              onTap: (_) {
                setState(() {
                  _selectedOpportunityId = null;
                });
              },
            ),

            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                child: _MapSearchBar(
                  onTap: _searchThisArea,
                ),
              ),
            ),

            if (_showSearchThisArea)
              Positioned(
                top: 86,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: _SearchThisAreaButton(
                      onTap: _searchThisArea,
                    ),
                  ),
                ),
              ),

            Positioned(
              right: 16,
              bottom: 184,
              child: SafeArea(
                child: _MapLocationButton(
                  onTap: () async {
                    await _mapController?.animateCamera(
                      CameraUpdate.newCameraPosition(
                        const CameraPosition(
                          target: _defaultCenter,
                          zoom: 13,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            _MapBottomSheet(
              docs: docs,
              selectedDoc: selectedDoc,
              onSelect: (doc) => _selectOpportunity(
                doc,
                animateCamera: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapSearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const _MapSearchBar({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Explore opportunities nearby',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchThisAreaButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchThisAreaButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.travel_explore_rounded),
      label: const Text('Search this area'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
      ),
    );
  }
}

class _MapLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MapLocationButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'opportunity-map-location',
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primary,
      elevation: 8,
      onPressed: onTap,
      child: const Icon(Icons.my_location_rounded),
    );
  }
}

class _MapBottomSheet extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onSelect;

  const _MapBottomSheet({
    required this.docs,
    required this.selectedDoc,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final shownDocs = selectedDoc == null ? docs : [selectedDoc!];

    return DraggableScrollableSheet(
      initialChildSize: selectedDoc == null ? 0.24 : 0.30,
      minChildSize: 0.16,
      maxChildSize: 0.72,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              16,
              10,
              16,
              24,
            ),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                selectedDoc == null
                    ? '${docs.length} nearby opportunities'
                    : 'Selected opportunity',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const _MapEmptyState(),
              ...shownDocs.map((doc) {
                return _MapOpportunityCard(
                  opportunityId: doc.id,
                  data: doc.data(),
                  selected: selectedDoc?.id == doc.id,
                  onSelect: () => onSelect(doc),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _MapOpportunityCard extends StatelessWidget {
  final String opportunityId;
  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onSelect;

  const _MapOpportunityCard({
    required this.opportunityId,
    required this.data,
    required this.selected,
    required this.onSelect,
  });

  String _formatDate(dynamic value) {
    if (value is! Timestamp) {
      return 'Date to be confirmed';
    }

    final date = value.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/${date.year} at $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title']?.toString() ?? 'Opportunity';
    final description = data['description']?.toString() ?? '';
    final category = data['category']?.toString() ?? 'Local';
    final location =
        data['location']?.toString() ?? 'Location to be confirmed';
    final organiserName =
        data['organiserName']?.toString() ?? 'Local organiser';
    final attendeeCount = data['attendeeCount'] ?? 0;
    final commentCount = data['commentCount'] ?? 0;
    final dateText = _formatDate(data['eventDate']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(selected ? 0.12 : 0.05),
                blurRadius: selected ? 22 : 12,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CategoryPill(category: category),
                  const Spacer(),
                  _MiniStat(
                    icon: Icons.people_alt_rounded,
                    text: '$attendeeCount',
                  ),
                  const SizedBox(width: 10),
                  _MiniStat(
                    icon: Icons.mode_comment_outlined,
                    text: '$commentCount',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                  height: 1.1,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SheetInfoRow(
                icon: Icons.calendar_month_rounded,
                text: dateText,
              ),
              const SizedBox(height: 8),
              _SheetInfoRow(
                icon: Icons.place_rounded,
                text: location,
              ),
              const SizedBox(height: 8),
              _SheetInfoRow(
                icon: Icons.person_rounded,
                text: organiserName,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OpportunityDetailScreen(
                          opportunityId: opportunityId,
                          opportunity: data,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'View opportunity',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String category;

  const _CategoryPill({
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniStat({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: Colors.black54,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SheetInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SheetInfoRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 19,
          color: AppColors.primary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapEmptyState extends StatelessWidget {
  const _MapEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 10),
      child: Text(
        'No opportunities with map locations yet.',
        style: TextStyle(
          color: Colors.black54,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MapMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 42,
              color: AppColors.primary,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}