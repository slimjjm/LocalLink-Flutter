class ActivityCategories {
  const ActivityCategories._();

  static const all = 'All';

  static const values = [
    'Fitness & Sport',
    'Family',
    'Pets',
    'Hobbies',
    'Social',
    'Volunteering',
    'Learning',
    'Local Deals',
    'Wellbeing & Support',
    'Outdoors',
    'Other',
  ];

  static const filters = [all, ...values];

  static const aliases = {
    'children & family': 'Family',
    'community & volunteering': 'Volunteering',
    'support & wellbeing': 'Wellbeing & Support',
    'hobbies & interests': 'Hobbies',
    'education & skills': 'Learning',
    'pets & animals': 'Pets',
    'sport & fitness': 'Fitness & Sport',
    'youth': 'Family',
    'community': 'Volunteering',
    'wellbeing': 'Wellbeing & Support',
  };

  static const tagSuggestions = {
    'Fitness & Sport': [
      'Football',
      'Rugby',
      'Hockey',
      'Running',
      'Cycling',
      'Swimming',
      'Martial Arts',
      'Dance',
      'Gymnastics',
      'Walking',
      'Fitness',
      'Beginner Friendly',
    ],
    'Family': [
      'Baby',
      'Toddler',
      'Children',
      'Youth',
      'Teenagers',
      'Parents',
      'Family',
      'Scouts',
      'Guides',
      'Toddler Group',
      'Playgroup',
    ],
    'Social': [
      'Friendship',
      'Meet Up',
      'Coffee',
      'Men',
      'Women',
      'Older Adults',
      'Social',
      'Community',
    ],
    'Volunteering': [
      'Volunteer',
      'Litter Picking',
      'Charity',
      'Community',
      'Fundraising',
      'Gardening',
      'Environment',
    ],
    'Wellbeing & Support': [
      'Wellbeing',
      'Mental Health',
      'Carers',
      'Dementia',
      'Memory',
      'Disability',
      'Support',
      'Bereavement',
    ],
    'Hobbies': [
      'Photography',
      'Crafts',
      'Art',
      'Music',
      'Chess',
      'Gaming',
      'Books',
      'Gardening',
      'Drama',
      'Craft',
    ],
    'Outdoors': [
      'Walking',
      'Nature',
      'Outdoor',
      'Adventure',
      'Cycling',
      'Community',
    ],
    'Learning': ['Education', 'Skills', 'Workshop', 'Beginners', 'Training'],
    'Pets': ['Dogs', 'Pets', 'Animals', 'Walking', 'Training', 'Social'],
  };

  static String normalise(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    for (final category in values) {
      if (category.toLowerCase() == trimmed.toLowerCase()) {
        return category;
      }
    }

    return aliases[trimmed.toLowerCase()] ?? trimmed;
  }

  static bool matchesFilter(String? storedCategory, String selectedFilter) {
    if (selectedFilter == all) return true;
    return normalise(storedCategory) == selectedFilter;
  }

  static List<String> suggestionsFor(String? category) {
    return tagSuggestions[normalise(category)] ?? const [];
  }
}
