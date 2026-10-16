import '../models/organisation.dart';
import 'activity_relationships.dart';

/// Populate Area has no private audience selector: it creates public listings.
/// Other creation screens keep their existing explicit audience controls.
class ModeratorPublicListingFields {
  const ModeratorPublicListingFields._();

  static const organisation = <String, Object?>{
    'visibility': 'public',
    'isPubliclyDiscoverable': true,
    'discoveryVisibility': 'public',
  };

  static Map<String, Object?> activity({Organisation? organisation}) => {
    ...ActivityRelationshipFields.build(
      organisation: organisation,
      audienceScope: 'everyone',
    ),
    'activityAudienceScope': 'everyone',
    'isPubliclyDiscoverable': true,
    'visibility': 'public',
  };
}
