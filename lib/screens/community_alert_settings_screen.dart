import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/address_result.dart';
import '../services/address_search_service.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';

const communityAlertCategories = {
  'missingDogs': 'Missing dogs',
  'missingCats': 'Missing cats',
  'otherMissingPets': 'Other missing pets',
  'importantLostItems': 'Important lost items',
  'otherLostItems': 'Other lost items',
};

const communityAlertRadiusOptions = [1, 3, 5, 10];

class CommunityAlertSettingsScreen extends StatefulWidget {
  const CommunityAlertSettingsScreen({super.key});

  @override
  State<CommunityAlertSettingsScreen> createState() =>
      _CommunityAlertSettingsScreenState();
}

class _CommunityAlertSettingsScreenState
    extends State<CommunityAlertSettingsScreen> {
  final _addressSearch = AddressSearchService();
  final _areaController = TextEditingController();

  bool _enabled = true;
  bool _isSaving = false;
  bool _isLocating = false;
  int _radiusMiles = 3;
  double? _latitude;
  double? _longitude;
  List<AddressResult> _suggestions = [];
  final Set<String> _enabledCategories = communityAlertCategories.keys.toSet();

  DocumentReference<Map<String, dynamic>>? get _subscriptionRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    return FirebaseFirestore.instance
        .collection('communityAlertSubscriptions')
        .doc(user.uid);
  }

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _searchArea(String query) async {
    final trimmed = query.trim();
    _latitude = null;
    _longitude = null;

    if (trimmed.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    final results = await _addressSearch.search(trimmed);
    if (!mounted) return;
    setState(() => _suggestions = results.take(5).toList());
  }

  Future<void> _selectArea(AddressResult suggestion) async {
    final coords = await _addressSearch.getCoordinates(suggestion.placeId);
    if (!mounted || coords == null) return;

    setState(() {
      _latitude = coords['lat'];
      _longitude = coords['lng'];
      _areaController.text = suggestion.description;
      _suggestions = [];
    });
  }

  Future<void> _useCurrentArea() async {
    setState(() => _isLocating = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (!mounted || position == null) return;

      setState(() {
        _latitude = double.parse(position.latitude.toStringAsFixed(3));
        _longitude = double.parse(position.longitude.toStringAsFixed(3));
        _areaController.text = 'Near my current area';
        _suggestions = [];
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _save() async {
    final ref = _subscriptionRef;
    if (ref == null) return;

    if (_enabled && (_latitude == null || _longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an alert area first.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = FieldValue.serverTimestamp();
      final categories = _enabledCategories.toList()..sort();

      await ref.set({
        'userId': FirebaseAuth.instance.currentUser!.uid,
        'communityAlertsEnabled': _enabled,
        'enabledCategories': _enabled ? categories : <String>[],
        'categoryPreferences': {
          for (final entry in communityAlertCategories.entries)
            entry.key: _enabledCategories.contains(entry.key),
        },
        'subscriptionType': 'chosenArea',
        'approxLatitude': _latitude ?? 0,
        'approxLongitude': _longitude ?? 0,
        'placeLabel': _areaController.text.trim(),
        'maxRadiusMiles': _radiusMiles,
        'isActive': _enabled,
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Community alert settings saved.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _load(Map<String, dynamic>? data) {
    if (data == null) return;

    _enabled = data['communityAlertsEnabled'] is bool
        ? data['communityAlertsEnabled'] == true
        : true;
    _radiusMiles = (data['maxRadiusMiles'] as num?)?.toInt() ?? 3;
    _latitude = (data['approxLatitude'] as num?)?.toDouble();
    _longitude = (data['approxLongitude'] as num?)?.toDouble();
    _areaController.text = data['placeLabel']?.toString() ?? '';
    final savedCategories = data['enabledCategories'];
    _enabledCategories
      ..clear()
      ..addAll(
        savedCategories is Iterable
            ? List<String>.from(savedCategories)
            : communityAlertCategories.keys,
      );
  }

  @override
  Widget build(BuildContext context) {
    final ref = _subscriptionRef;
    if (ref == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Community Alerts')),
      backgroundColor: AppColors.background,
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: ref.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !_isSaving &&
              _areaController.text.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData && _areaController.text.isEmpty) {
            _load(snapshot.data!.data());
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Choose the area where missing and found alerts should reach you. Your chosen area is used straight away. If you use your current area, LocalLink only treats it as an alert area after you have been nearby for a little while, so passing through somewhere does not trigger extra alerts.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _enabled,
                title: const Text('Nearby missing & found alerts'),
                subtitle: const Text(
                  'Uses an approximate area and avoids constant background location.',
                ),
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 12),
              ...communityAlertCategories.entries.map((entry) {
                return CheckboxListTile(
                  value: _enabledCategories.contains(entry.key),
                  title: Text(entry.value),
                  onChanged: _enabled
                      ? (value) {
                          setState(() {
                            if (value == true) {
                              _enabledCategories.add(entry.key);
                            } else {
                              _enabledCategories.remove(entry.key);
                            }
                          });
                        }
                      : null,
                );
              }),
              const SizedBox(height: 14),
              const Text(
                'Alert me near',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _areaController,
                enabled: _enabled,
                onChanged: _searchArea,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Search area or landmark',
                ),
              ),
              if (_suggestions.isNotEmpty)
                ..._suggestions.map(
                  (suggestion) => ListTile(
                    title: Text(suggestion.description),
                    onTap: () => _selectArea(suggestion),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _enabled && !_isLocating ? _useCurrentArea : null,
                icon: _isLocating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_outlined),
                label: const Text('Use my current area'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Maximum alert radius',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: communityAlertRadiusOptions.map((radius) {
                  return ChoiceChip(
                    label: Text('$radius mi'),
                    selected: _radiusMiles == radius,
                    onSelected: _enabled
                        ? (_) => setState(() => _radiusMiles = radius)
                        : null,
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Save settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.buttonText,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
