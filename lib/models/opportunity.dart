class Opportunity {

  final String id;
  final String title;
  final String category;
  final String description;
  final String organiser;

  Opportunity({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.organiser,
  });

  factory Opportunity.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {

    return Opportunity(
      id: id,
      title: data['title'] ?? '',
      category: data['category'] ?? '',
      description: data['description'] ?? '',
      organiser: data['organiser'] ?? '',
    );
  }
}