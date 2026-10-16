class BusinessCategories {
  const BusinessCategories._();

  static const values = [
    'Aesthetics',
    'Beauty',
    'Brows & Lashes',
    'Hair Salon',
    'Barber',
    'Nails',
    'Massage',
    'Skin Clinic',
    'Cleaner',
    'Dog Groomer',
    'Dog Walker',
    'Gardener',
    'Handyman',
    'Mobile Valeting',
    'Pressure Washing',
    'Specialist Services',
  ];

  static String normalise(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    for (final category in values) {
      if (category.toLowerCase() == trimmed.toLowerCase()) {
        return category;
      }
    }

    return trimmed;
  }

  static bool isCanonical(String? value) {
    final trimmed = value?.trim() ?? '';
    return values.any((category) => category == trimmed);
  }
}
