import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../screens/opportunity_detail_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';

class OpportunityMapView extends StatefulWidget {
  const OpportunityMapView({super.key});

  @override
  State<OpportunityMapView> createState() => _OpportunityMapViewState();
}

class _OpportunityMapViewState extends State<OpportunityMapView> {
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};

  String? _selectedItemKey;
  bool _showSearchThisArea = false;
  Position? _currentPosition;
  bool _locationLookupInProgress = false;

  static const LatLng _ukFallbackCenter = LatLng(54.5, -3.0);

  Stream<QuerySnapshot<Map<String, dynamic>>> get _opportunityStream {
    return FirebaseFirestore.instance
        .collection('opportunities')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _communityHelpStream {
    return FirebaseFirestore.instance
        .collection('communityHelpPosts')
        .where('type', isEqualTo: 'lost_found')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation(animate: false);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<Position?> _loadCurrentLocation({required bool animate}) async {
    if (_locationLookupInProgress) {
      return _currentPosition;
    }

    setState(() {
      _locationLookupInProgress = true;
    });

    try {
      final position = await LocationService().getCurrentLocation();
      if (!mounted) return position;

      setState(() {
        _currentPosition = position;
      });

      if (animate && position != null) {
        await _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 14,
            ),
          ),
        );
      }

      return position;
    } finally {
      if (mounted) {
        setState(() {
          _locationLookupInProgress = false;
        });
      }
    }
  }

  double? _readDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  LatLng? _latLngFromData(Map<String, dynamic> data) {
    final latitude =
        _readDouble(data, 'latitude') ?? _readDouble(data, 'approxLatitude');
    final longitude =
        _readDouble(data, 'longitude') ?? _readDouble(data, 'approxLongitude');

    if (latitude == null || longitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  bool _isActiveCommunityHelp(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'active';
    final expiresAt = data['expiresAt'];

    if (data['isActive'] == false ||
        status == 'resolved' ||
        status == 'expired' ||
        data['resolvedAt'] != null) {
      return false;
    }

    if (expiresAt is Timestamp) {
      return expiresAt.toDate().isAfter(DateTime.now());
    }

    return true;
  }

  bool _isFutureOpportunity(Map<String, dynamic> data) {
    final eventDate = data['eventDate'];

    if (eventDate is Timestamp) {
      return eventDate.toDate().isAfter(DateTime.now());
    }

    return true;
  }

  List<_MapItem> _mappableItems({
    required QuerySnapshot<Map<String, dynamic>> opportunities,
    required QuerySnapshot<Map<String, dynamic>> communityHelpPosts,
  }) {
    final items = <_MapItem>[];

    for (final doc in opportunities.docs) {
      final data = doc.data();
      if (_latLngFromData(data) == null || !_isFutureOpportunity(data)) {
        continue;
      }

      items.add(_MapItem(id: doc.id, kind: _MapItemKind.activity, data: data));
    }

    for (final doc in communityHelpPosts.docs) {
      final data = doc.data();
      if (_latLngFromData(data) == null || !_isActiveCommunityHelp(data)) {
        continue;
      }

      items.add(
        _MapItem(id: doc.id, kind: _MapItemKind.communityHelp, data: data),
      );
    }

    return items;
  }

  void _refreshMarkers(List<_MapItem> items) {
    final markers = items.map((item) {
      final selected = item.key == _selectedItemKey;
      final isCommunity = item.kind == _MapItemKind.communityHelp;
      final mode = item.data['mode']?.toString() ?? 'lost';
      final hue = isCommunity
          ? mode == 'lost'
                ? BitmapDescriptor.hueRed
                : BitmapDescriptor.hueGreen
          : BitmapDescriptor.hueAzure;

      return Marker(
        markerId: MarkerId(item.key),
        position: _latLngFromData(item.data)!,
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        zIndexInt: selected
            ? 100
            : isCommunity
            ? 20
            : 1,
        infoWindow: InfoWindow.noText,
        onTap: () => _selectItem(item, animateCamera: true),
      );
    }).toSet();

    setState(() {
      _markers = markers;
    });
  }

  Future<void> _selectItem(_MapItem item, {required bool animateCamera}) async {
    final latLng = _latLngFromData(item.data);

    setState(() {
      _selectedItemKey = item.key;
    });

    if (animateCamera && latLng != null) {
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 14.5),
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

  _MapItem? _selectedItemFrom(List<_MapItem> items) {
    if (_selectedItemKey == null) {
      return null;
    }

    for (final item in items) {
      if (item.key == _selectedItemKey) {
        return item;
      }
    }

    return null;
  }

  LatLng _initialCenter(List<_MapItem> items) {
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    final mappable = items
        .map((item) => _latLngFromData(item.data))
        .whereType<LatLng>()
        .toList();

    if (mappable.isEmpty) {
      return _ukFallbackCenter;
    }

    final lat =
        mappable.map((point) => point.latitude).reduce((a, b) => a + b) /
        mappable.length;
    final lng =
        mappable.map((point) => point.longitude).reduce((a, b) => a + b) /
        mappable.length;

    return LatLng(lat, lng);
  }

  Future<void> _centerOnCurrentLocation() async {
    final position =
        _currentPosition ?? await _loadCurrentLocation(animate: true);

    if (position != null) {
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 14,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'We could not get your current location. Showing nearby public posts instead.',
        ),
      ),
    );
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
            message: 'Something went wrong loading nearby activity.',
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _communityHelpStream,
          builder: (context, communitySnapshot) {
            if (communitySnapshot.hasError) {
              return const _MapMessage(
                icon: Icons.error_outline_rounded,
                title: 'Map could not load',
                message: 'Something went wrong loading nearby help posts.',
              );
            }

            if (!communitySnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = _mappableItems(
              opportunities: snapshot.data!,
              communityHelpPosts: communitySnapshot.data!,
            );
            if (_markers.length != items.length ||
                !_markers
                    .map((marker) => marker.markerId.value)
                    .toSet()
                    .containsAll(items.map((item) => item.key))) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _refreshMarkers(items);
              });
            }
            final selectedItem = _selectedItemFrom(items);

            return Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _initialCenter(items),
                    zoom: _currentPosition == null && items.isEmpty
                        ? 5.5
                        : _currentPosition == null
                        ? 12
                        : 13,
                  ),
                  markers: _markers,
                  myLocationEnabled: _currentPosition != null,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  mapType: MapType.normal,
                  compassEnabled: false,
                  buildingsEnabled: true,
                  trafficEnabled: false,
                  indoorViewEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
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
                      _selectedItemKey = null;
                    });
                  },
                ),

                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: SafeArea(child: _MapSearchBar(onTap: _searchThisArea)),
                ),

                if (_showSearchThisArea)
                  Positioned(
                    top: 86,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Center(
                        child: _SearchThisAreaButton(onTap: _searchThisArea),
                      ),
                    ),
                  ),

                Positioned(
                  right: 16,
                  bottom: 184,
                  child: SafeArea(
                    child: _MapLocationButton(onTap: _centerOnCurrentLocation),
                  ),
                ),

                _MapBottomSheet(
                  items: items,
                  selectedItem: selectedItem,
                  onSelect: (item) => _selectItem(item, animateCamera: true),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum _MapItemKind { activity, communityHelp }

class _MapItem {
  const _MapItem({required this.id, required this.kind, required this.data});

  final String id;
  final _MapItemKind kind;
  final Map<String, dynamic> data;

  String get key => '${kind.name}_$id';
}

class _MapSearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const _MapSearchBar({required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Explore activities nearby',
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
                  color: AppColors.primary.withValues(alpha: 0.10),
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

  const _SearchThisAreaButton({required this.onTap});

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }
}

class _MapLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MapLocationButton({required this.onTap});

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
  final List<_MapItem> items;
  final _MapItem? selectedItem;
  final ValueChanged<_MapItem> onSelect;

  const _MapBottomSheet({
    required this.items,
    required this.selectedItem,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final shownItems = selectedItem == null ? items : [selectedItem!];

    return DraggableScrollableSheet(
      initialChildSize: selectedItem == null ? 0.24 : 0.30,
      minChildSize: 0.16,
      maxChildSize: 0.72,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
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
                selectedItem == null
                    ? '${items.length} nearby map items'
                    : selectedItem!.kind == _MapItemKind.communityHelp
                    ? 'Selected help post'
                    : 'Selected activity',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty) const _MapEmptyState(),
              ...shownItems.map((item) {
                if (item.kind == _MapItemKind.communityHelp) {
                  return _MapCommunityHelpCard(
                    postId: item.id,
                    data: item.data,
                    selected: selectedItem?.key == item.key,
                    onSelect: () => onSelect(item),
                  );
                }

                return _MapOpportunityCard(
                  opportunityId: item.id,
                  data: item.data,
                  selected: selectedItem?.key == item.key,
                  onSelect: () => onSelect(item),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _MapCommunityHelpCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onSelect;

  const _MapCommunityHelpCard({
    required this.postId,
    required this.data,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final mode = data['mode']?.toString() ?? 'lost';
    final isLost = mode == 'lost';
    final title = data['title']?.toString() ?? 'Community Help post';
    final description = data['description']?.toString() ?? '';
    final category = data['itemCategory']?.toString() ?? 'Item';
    final location =
        data['publicLocation']?.toString() ??
        data['location']?.toString() ??
        'Approximate area';
    final label = isLost ? 'LOST' : 'FOUND';

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
                color: Colors.black.withValues(alpha: selected ? 0.12 : 0.05),
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
                  _CategoryPill(category: label),
                  const SizedBox(width: 8),
                  _CategoryPill(category: category),
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
              _SheetInfoRow(icon: Icons.place_rounded, text: location),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PostServiceRequestScreen(initialPostId: postId),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Open Community Help',
                    style: TextStyle(fontWeight: FontWeight.w900),
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
    final title = data['title']?.toString() ?? 'Activity';
    final description = data['description']?.toString() ?? '';
    final category = data['category']?.toString() ?? 'Local';
    final location = data['location']?.toString() ?? 'Location to be confirmed';
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
                color: Colors.black.withValues(alpha: selected ? 0.12 : 0.05),
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
              _SheetInfoRow(icon: Icons.calendar_month_rounded, text: dateText),
              const SizedBox(height: 8),
              _SheetInfoRow(icon: Icons.place_rounded, text: location),
              const SizedBox(height: 8),
              _SheetInfoRow(icon: Icons.person_rounded, text: organiserName),
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
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'View activity',
                    style: TextStyle(fontWeight: FontWeight.w900),
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

  const _CategoryPill({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
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

  const _MiniStat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Colors.black54),
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

  const _SheetInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.primary),
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
        'No activities or help posts with map locations yet.',
        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
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
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.primary),
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
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
