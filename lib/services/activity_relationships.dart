import '../models/organisation.dart';
import '../models/organisation_group.dart';

class ActivityRelationshipFields {
  const ActivityRelationshipFields._();

  static Map<String, Object?> build({
    Organisation? organisation,
    OrganisationGroup? group,
    String activityKind = 'activity',
    String audienceScope = 'everyone',
    String opponentName = '',
    String fixtureVenue = 'home',
  }) {
    final normalisedKind = normaliseActivityKind(activityKind);
    final normalisedAudienceScope = normaliseAudienceScope(
      organisation == null
          ? 'everyone'
          : group != null
          ? 'group'
          : audienceScope,
    );
    return {
      'activityContext': group != null
          ? 'group'
          : organisation != null
          ? 'organisation'
          : 'standalone',
      'activityKind': normalisedKind,
      'discoveryVisibility': normalisedAudienceScope == 'everyone'
          ? 'public'
          : 'restricted',
      if (organisation != null) ...{
        'activityAudienceScope': normalisedAudienceScope,
        'isPubliclyDiscoverable': normalisedAudienceScope == 'everyone',
        'organisationId': organisation.id,
        'organisationName': organisation.name,
        'organisationCategory': organisation.category,
        'organisationSubcategories': organisation.subcategories,
        'organisationImageUrl': organisation.imageUrl,
        'organisationLocation': organisation.publicLocation,
      },
      if (group != null) ...{
        'groupId': group.id,
        'groupName': group.name,
        'groupDisplayType': group.displayType,
        'groupAgeLabel': group.ageLabel,
        'groupLeaderUserIds': group.leaderUserIds,
      },
      if (normalisedKind == 'fixture') ...{
        'opponentName': opponentName.trim(),
        'fixtureVenue': normaliseFixtureVenue(fixtureVenue),
      },
    };
  }

  static String normaliseActivityKind(String value) {
    return switch (value) {
      'session' => 'session',
      'event' => 'event',
      'fixture' => 'fixture',
      'community_challenge' => 'community_challenge',
      _ => 'activity',
    };
  }

  static String normaliseFixtureVenue(String value) {
    return switch (value) {
      'away' => 'away',
      'neutral' => 'neutral',
      _ => 'home',
    };
  }

  static String normaliseAudienceScope(String value) {
    return switch (value) {
      'organisation' => 'organisation',
      'group' => 'group',
      _ => 'everyone',
    };
  }
}
