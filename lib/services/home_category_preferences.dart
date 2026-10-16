import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_feed_rules.dart';

abstract interface class HomeCategoryPreferences {
  Future<HomeDiscoveryCategory?> load();

  Future<void> save(HomeDiscoveryCategory category);
}

class DeviceHomeCategoryPreferences implements HomeCategoryPreferences {
  DeviceHomeCategoryPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  final SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  String get _key {
    final user = FirebaseAuth.instance.currentUser;
    final scope = user == null || user.isAnonymous ? 'guest' : user.uid;
    return 'home.selected_category.$scope';
  }

  @override
  Future<HomeDiscoveryCategory?> load() async {
    try {
      final stored = await _store.getString(_key);
      if (stored == null) return null;
      for (final category in HomeDiscoveryCategory.values) {
        if (category.name == stored) return category;
      }
      return null;
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> save(HomeDiscoveryCategory category) async {
    try {
      await _store.setString(_key, category.name);
    } on StateError {
      // Keep Home usable with its Nearby default when local storage is absent.
    }
  }
}
