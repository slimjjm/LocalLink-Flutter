"use strict";

const ASK_MODEL = process.env.ASK_LOCALLINK_MODEL || "gpt-4.1-mini";
const MAX_QUERY_LENGTH = 240;
const DEFAULT_LIMIT = 12;
const DEFAULT_LOCAL_BUSINESS_RADIUS_MILES = 40;
const DEFAULT_PET_DISCOVERY_RADIUS_MILES = 10;
const DEFAULT_COMMUNITY_HELP_DISCOVERY_RADIUS_MILES = 5;

const INTENTS = new Set([
  "find_service",
  "find_availability",
  "find_activity",
  "find_organisation",
  "find_community_help",
  "report_missing_pet",
  "report_lost_item",
  "report_found_item",
  "give_away_item",
  "create_activity",
  "list_business",
  "unknown",
]);

const ACTION_INTENTS = new Set([
  "report_missing_pet",
  "report_lost_item",
  "report_found_item",
  "give_away_item",
  "create_activity",
  "list_business",
]);

const RESULT_ROUTES = {
  service: ({ id, parentId }) => `/businesses/${parentId}?serviceId=${id}`,
  business: ({ id }) => `/businesses/${id}`,
  availability: ({ id }) => `/availability/${id}`,
  activity: ({ id }) => `/opportunities/${id}`,
  organisation: ({ id }) => `/organisations/${id}`,
  group: ({ parentId, id }) => `/organisations/${parentId}/groups/${id}`,
  communityHelp: ({ id }) => `/community-help/${id}`,
  action: ({ id }) => `/actions/${id}`,
};

const ACTION_DEFINITIONS = {
  report_missing_pet: {
    title: "Report missing pet",
    subtitle: "Sorry your pet is missing. You can alert people nearby on LocalLink.",
    metadata: {
      communityHelpType: "lost_found",
      mode: "lost",
      itemCategory: "Pet",
    },
  },
  report_lost_item: {
    title: "Report lost item",
    subtitle: "You can let nearby people know what was lost and where to look.",
    metadata: {
      communityHelpType: "lost_found",
      mode: "lost",
      itemCategory: "Other",
    },
  },
  report_found_item: {
    title: "Report found item",
    subtitle: "You can report it as found so the owner can find the post.",
    metadata: {
      communityHelpType: "lost_found",
      mode: "found",
      itemCategory: "Other",
    },
  },
  give_away_item: {
    title: "Give away item",
    subtitle: "You can offer it free to people nearby on LocalLink.",
    metadata: {
      communityHelpType: "free_item",
      mode: "offering",
      itemCategory: "Free item",
    },
  },
  create_activity: {
    title: "Create activity",
    subtitle: "Add your class, session or event so local people can find it.",
    metadata: {},
  },
  list_business: {
    title: "List your business",
    subtitle: "Create a LocalLink business page so local customers can find you.",
    metadata: {},
  },
};

function safeText(value, max = 160) {
  const text = String(value ?? "").replace(/\s+/g, " ").trim();
  return text.length > max ? text.slice(0, max).trim() : text;
}

function normaliseText(value) {
  return safeText(value, 400).toLowerCase();
}

function normaliseSearchToken(value) {
  const token = normaliseText(value)
    .replace(/^[^a-z0-9]+|[^a-z0-9]+$/g, "");
  return token.endsWith("s") && token.length > 3 ? token.slice(0, -1) : token;
}

function toNumber(value) {
  if (value == null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isValidCoordinatePair(latitude, longitude) {
  const lat = toNumber(latitude);
  const lng = toNumber(longitude);
  if (lat == null || lng == null) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  return !(Math.abs(lat) < 0.000001 && Math.abs(lng) < 0.000001);
}

function coordinatePairFrom(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = toNumber(value.latitude);
  const longitude = toNumber(value.longitude);
  if (!isValidCoordinatePair(latitude, longitude)) return null;
  return { latitude, longitude };
}

function locationTextsCompatible(intentText, contextText) {
  const intent = normaliseText(intentText).replace(/^near\s+/, "");
  const context = normaliseText(contextText).replace(/^near\s+/, "");
  if (!intent) return true;
  if (!context) return false;
  return intent.includes(context) || context.includes(intent);
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function dateKeyInLondon(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/London",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function londonDateLabel(value) {
  const millis = timestampMillis(value);
  if (!millis) return "";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(millis));
}

function londonDateOnlyLabel(value) {
  const millis = timestampMillis(value);
  if (!millis) return "";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(new Date(millis));
}

function parseActivityEventTime(value) {
  const text = safeText(value, 20);
  if (!text) return null;

  const match = text.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i);
  if (!match) return null;

  let hour = Number(match[1]);
  const minute = Number(match[2] || "0");
  const suffix = safeText(match[3]).toLowerCase();
  if (hour > 23 || minute > 59) return null;
  if (suffix) {
    if (hour < 1 || hour > 12) return null;
    if (suffix === "pm" && hour !== 12) hour += 12;
    if (suffix === "am" && hour === 12) hour = 0;
  }

  return {
    hour,
    minute,
    label: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`,
  };
}

function londonTimeParts(value) {
  const millis = timestampMillis(value);
  if (!millis) return null;
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date(millis));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    hour: Number(values.hour),
    minute: Number(values.minute),
  };
}

function isLondonMidnight(value) {
  const parts = londonTimeParts(value);
  return parts != null && parts.hour === 0 && parts.minute === 0;
}

function activityDateTimeLabel(activity) {
  const dateValue = activity.eventDate ?? activity.startTime;
  const dateLabel = londonDateOnlyLabel(dateValue);
  if (!dateLabel) return "";

  const eventTime = parseActivityEventTime(activity.eventTime);
  if (eventTime) {
    return `${dateLabel}, ${eventTime.label}`;
  }

  return isLondonMidnight(dateValue) ? dateLabel : londonDateLabel(dateValue);
}

function activityResultDateTime(activity) {
  const millis = timestampMillis(activity.eventDate ?? activity.startTime);
  if (!millis) return "";

  const eventTime = parseActivityEventTime(activity.eventTime);
  if (!eventTime) {
    return isLondonMidnight(activity.eventDate ?? activity.startTime)
      ? ""
      : new Date(millis).toISOString();
  }

  const key = dateKeyInLondon(new Date(millis));
  return `${key}T${eventTime.label}:00`;
}

function addDays(date, days) {
  const next = new Date(date.getTime());
  next.setUTCDate(next.getUTCDate() + days);
  return next;
}

function nextWeekdayDateKey(now, weekday) {
  const today = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    weekday: "long",
  }).format(now).toLowerCase();
  const days = [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ];
  const currentIndex = days.indexOf(today);
  const targetIndex = days.indexOf(weekday);
  if (currentIndex < 0 || targetIndex < 0) return null;
  const delta = (targetIndex - currentIndex + 7) % 7 || 7;
  return dateKeyInLondon(addDays(now, delta));
}

function dateRangeFromQuery(query, now = new Date()) {
  const lower = normaliseText(query);
  if (lower.includes("today")) {
    const key = dateKeyInLondon(now);
    return { start: key, end: key };
  }
  if (lower.includes("tonight")) {
    const key = dateKeyInLondon(now);
    return { start: key, end: key };
  }
  if (lower.includes("tomorrow")) {
    const key = dateKeyInLondon(addDays(now, 1));
    return { start: key, end: key };
  }
  if (lower.includes("weekend")) {
    const saturday = nextWeekdayDateKey(now, "saturday");
    if (!saturday) return null;
    const sunday = dateKeyInLondon(addDays(new Date(`${saturday}T12:00:00Z`), 1));
    return { start: saturday, end: sunday };
  }
  for (const day of [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
  ]) {
    if (lower.includes(day)) {
      const key = nextWeekdayDateKey(now, day);
      return key ? { start: key, end: key } : null;
    }
  }
  return null;
}

function timeRangeFromQuery(query) {
  const lower = normaliseText(query);
  if (lower.includes("morning")) return { start: "06:00", end: "12:00" };
  if (lower.includes("afternoon")) return { start: "12:00", end: "17:00" };
  if (lower.includes("evening") || lower.includes("tonight")) return { start: "17:00", end: "22:00" };
  return null;
}

function hasDiscoveryCue(lower) {
  return /\b(are there|has anyone|anyone lost|any|find|show|search|looking for|near me|nearby|around me|do you know|where can i find|who's|who is|i need|need a|need an|need someone|available|availability)\b/.test(lower);
}

function hasCreateCue(lower) {
  return /\b(i am|i'm|im|we are|we're|were|i run|we run|i organise|we organise|i organize|we organize|i host|we host|i own|we own|my business|our business|want to list|want to add|add my|add our|list my|list our|advertise|put .* on here|join locallink|can i put)\b/.test(lower);
}

function lostFoundCategoryFromQuery(lower) {
  if (/\b(pet|dog|cat|rabbit|hamster|bird)\b/.test(lower)) return "Pet";
  if (/\bkey|keys\b/.test(lower)) return "Keys";
  if (/\bphone|mobile\b/.test(lower)) return "Phone";
  if (/\bwallet|purse\b/.test(lower)) return "Wallet";
  if (/\b(bike|bicycle|scooter)\b/.test(lower)) return "Bike / scooter";
  if (/\b(bag|rucksack|handbag)\b/.test(lower)) return "Bag";
  return "Other";
}

function petTypeFromQuery(lower) {
  const match = lower.match(/\b(dog|cat|rabbit|hamster|bird)\b/);
  return match ? match[1] : "";
}

function hasChallengeDiscoveryIntent(lower) {
  if (/\b(community\s+)?challenges?\b/.test(lower)) return true;
  if (/\b(competitions?|contests?)\b/.test(lower)) return true;
  if (/\b(photo|picture|pet|dog|cat|family|kids?|children)\b.*\b(challenges?|competitions?|contests?)\b/.test(lower)) return true;
  if (/\b(challenges?|competitions?|contests?)\b.*\b(photo|picture|pet|dog|cat|family|kids?|children)\b/.test(lower)) return true;
  if (/\b(closing soon|ending soon|still open)\b/.test(lower)) return true;
  if (/\b(entries|entry|enter|prizes?|win|giveaway)\b/.test(lower) &&
      /\b(any|anything|local|locally|near me|nearby|community|photo|picture|pet|dog|cat|family|kids?|children|open|closing|ending|challenges?|competitions?|contests?)\b/.test(lower)) {
    return true;
  }
  return false;
}

function hasChallengeEntryIntent(intent) {
  const lower = normaliseText([
    intent.searchText,
    intent.serviceType,
    intent.category,
  ].filter(Boolean).join(" "));
  if (/\b(any|show|find|local|near|nearby|are there)\b/.test(lower) &&
      /\b(challenges?|competitions?|contests?)\b/.test(lower)) {
    return true;
  }
  return hasChallengeDiscoveryIntent(lower) &&
    /\b(enter|entry|entries|competitions?|contests?|prizes?|win|giveaway|open|still open|closing soon|ending soon)\b/.test(lower);
}

function hasChallengeClosingSoonIntent(intent) {
  const lower = normaliseText([
    intent.searchText,
    intent.serviceType,
    intent.category,
  ].filter(Boolean).join(" "));
  return /\bclosing\s+soon\b/.test(lower) ||
    /\bending\s+soon\b/.test(lower) ||
    /\bclosing\s+this\s+week\b/.test(lower) ||
    /\bending\s+this\s+week\b/.test(lower) ||
    /\bstill\s+open\b/.test(lower);
}

function activityCategoryFromQuery(lower) {
  if (/\b(baby|babies|toddler|toddlers|child|children|kids|family)\b/.test(lower)) return "Family";
  if (/\b(fitness|yoga|pilates|football|sport|run|running|dance)\b/.test(lower)) return "Fitness & Sport";
  if (/\b(workshop|course|learn|learning|class)\b/.test(lower)) return "Learning";
  if (/\b(volunteer|community|charity)\b/.test(lower)) return "Volunteering";
  return "";
}

function businessCategoryFromQuery(lower) {
  if (/\b(hair salon|hairdresser|hair stylist|hairstylist)\b/.test(lower)) return "Hair Salon";
  if (/\bbarber\b/.test(lower)) return "Barber";
  if (/\bnail|nails\b/.test(lower)) return "Nails";
  if (/\bcleaner|cleaning\b/.test(lower)) return "Cleaner";
  if (/\bdog groomer|grooming\b/.test(lower)) return "Dog Groomer";
  if (/\bdog walker|dog walking\b/.test(lower)) return "Dog Walker";
  if (/\bgardener|gardening\b/.test(lower)) return "Gardener";
  if (/\bhandyman\b/.test(lower)) return "Handyman";
  if (/\b(massage|masseuse)\b/.test(lower)) return "Massage";
  if (/\b(plumber|electrician|decorator|painter|builder)\b/.test(lower)) return "Specialist Services";
  return "";
}

function inferActionIntent(query) {
  const lower = normaliseText(query);
  if (!lower || hasDiscoveryCue(lower)) return null;

  if (/\b(my|our)\b.*\b(pet|dog|cat|rabbit|hamster|bird)\b.*\b(missing|lost|got out|escaped|run away|ran away)\b/.test(lower) ||
      /\b(i|we|i've|ive|we've|weve|i have|we have)\b.*\b(lost)\b.*\b(pet|dog|cat|rabbit|hamster|bird)\b/.test(lower)) {
    return "report_missing_pet";
  }
  if (/\b(i|we|i've|ive|we've|weve|i have|we have)\b.*\b(found)\b/.test(lower)) {
    return "report_found_item";
  }
  if (/\b(i|we|i've|ive|we've|weve|i have|we have)\b.*\b(lost|misplaced)\b/.test(lower)) {
    return "report_lost_item";
  }
  if (/\b(give away|giving away|free to collect|offer .* free|offering .* free)\b/.test(lower)) {
    return "give_away_item";
  }
  if (
    hasCreateCue(lower) &&
    /\b(activity|class|event|session|club|group|workshop)\b/.test(lower)
  ) {
    return "create_activity";
  }
  if (
    hasCreateCue(lower) &&
    /\b(business|service|plumber|electrician|cleaner|hairdresser|salon|barber|nails|gardener|handyman|groomer|walker|decorator|painter)\b/.test(lower)
  ) {
    return "list_business";
  }
  return null;
}

function inferIntent(query) {
  const lower = normaliseText(query);
  if (!lower || ["hello", "hi", "hey"].includes(lower)) return "unknown";
  const actionIntent = inferActionIntent(query);
  if (actionIntent) return actionIntent;
  if (hasChallengeDiscoveryIntent(lower)) {
    return "find_activity";
  }
  if (/(missing|lost|found|keys|property|free item|dog nearby|cat nearby)/.test(lower)) {
    return "find_community_help";
  }
  if (/(available|availability|appointment|cancellation|slot|space|today|tomorrow|tonight|this afternoon|this morning)/.test(lower)) {
    return "find_availability";
  }
  if (tokenLikeAny(lower, ["club", "scout", "organisation", "organization", "group", "society"])) {
    return "find_organisation";
  }
  if (/(activity|event|class|happening|football|fitness|run|running|child|children|baby|babies|toddler|toddlers|kids|family|year old|morning|weekend|saturday|sunday|cafe)/.test(lower)) {
    return "find_activity";
  }
  if (
    /(cleaner|groomer|plumber|hairdresser|nail|oven|electrician|gardener|decorator|service|near me|within)/.test(lower) ||
    tokenLikeAny(lower, ["cleaner", "groomer", "plumber", "hairdresser", "electrician", "gardener", "decorator"])
  ) {
    return "find_service";
  }
  return "unknown";
}

function hasStructuralGroupIntent(query) {
  return tokenLikeAny(normaliseText(query), [
    "club",
    "group",
    "organisation",
    "organization",
    "society",
  ]);
}

function hasCommunityHelpIntent(query) {
  return /\b(missing|lost|found|keys|property|free item|free sofa|free table|free chair|dog nearby|cat nearby)\b/.test(normaliseText(query));
}

function stripIntentWords(query) {
  return safeText(query)
    .replace(/\b(today|tomorrow|tonight|this|morning|afternoon|evening|weekend|saturday|sunday|monday|tuesday|wednesday|thursday|friday|available|availability|appointment|appointments|cancellation|cancellations|slot|slots|space|spaces|near me|within \d+ miles?)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function locationTextFromQuery(query) {
  const capped = safeText(query, MAX_QUERY_LENGTH);
  const match = capped.match(/\b(?:in|near|around)\s+([a-zA-Z][a-zA-Z\s'-]{2,60})$/i);
  if (!match) return "";
  return safeText(
    match[1]
      .replace(/\b(today|tomorrow|tonight|this|morning|afternoon|evening|weekend|saturday|sunday|monday|tuesday|wednesday|thursday|friday)\b/gi, " ")
      .replace(/\s+/g, " "),
    80
  );
}

function heuristicIntent(query, now = new Date()) {
  const capped = safeText(query, MAX_QUERY_LENGTH);
  const lower = normaliseText(capped);
  const ageMatch = lower.match(/\b(\d{1,2})\s*(year old|yo|yrs? old)\b/);
  const radiusMatch = lower.match(/within\s+(\d{1,2})\s*miles?/);
  const intent = inferIntent(capped);
  return normaliseIntent({
    intent,
    searchText: stripIntentWords(capped),
    serviceType: stripIntentWords(capped),
    dateRange: dateRangeFromQuery(capped, now),
    timeRange: timeRangeFromQuery(capped),
    location: {
      text: locationTextFromQuery(capped) || (lower.includes("burntwood") ? "Burntwood" : lower.includes("lichfield") ? "Lichfield" : ""),
      radiusMiles: radiusMatch ? Number(radiusMatch[1]) : null,
    },
    requiresAvailability: intent === "find_availability" || lower.includes("available") || lower.includes("cancellation"),
    allowDiscoveryFallback: intent === "find_availability" &&
      !/\b(available|availability|appointment|appointments|cancellation|cancellations|slot|slots)\b/.test(lower),
    audience: /child|children|year old|family/.test(lower) ? "children" : "",
    age: ageMatch ? Number(ageMatch[1]) : null,
    sort: intent === "find_availability" ? "soonest" : lower.includes("near") ? "nearest" : "relevance",
    confidence: intent === "unknown" ? 0.2 : 0.62,
  }, capped, now);
}

function normaliseDateRange(value) {
  if (!value || typeof value !== "object") return null;
  const start = safeText(value.start, 10);
  const end = safeText(value.end || value.start, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(end)) {
    return null;
  }
  return { start, end };
}

function normaliseTimeRange(value) {
  if (!value || typeof value !== "object") return null;
  const start = safeText(value.start, 5);
  const end = safeText(value.end, 5);
  if (!/^\d{2}:\d{2}$/.test(start) || !/^\d{2}:\d{2}$/.test(end)) {
    return null;
  }
  return { start, end };
}

function normaliseLocation(value, fallback = {}) {
  const raw = value && typeof value === "object" ? value : {};
  const radius = toNumber(raw.radiusMiles ?? fallback.radiusMiles);
  const coordinates = coordinatePairFrom(raw) || coordinatePairFrom(fallback);
  return {
    text: safeText(raw.text ?? fallback.text, 80),
    latitude: coordinates?.latitude ?? null,
    longitude: coordinates?.longitude ?? null,
    radiusMiles: radius && radius > 0 && radius <= 50 ? radius : null,
  };
}

function applyAuthoritativeLocation(intent, { context = {} } = {}) {
  const currentLocation = intent.location || {};
  const contextCoordinates = coordinatePairFrom(context);
  const contextText = safeText(context.locationText, 80);
  const contextRadius = toNumber(context.radiusMiles);
  const requestedRadius = currentLocation.radiusMiles ??
    (contextRadius && contextRadius > 0 && contextRadius <= 50 ? contextRadius : null);

  if (
    contextCoordinates &&
    locationTextsCompatible(currentLocation.text, contextText)
  ) {
    return {
      ...intent,
      location: {
        ...currentLocation,
        text: safeText(currentLocation.text || contextText, 80),
        latitude: contextCoordinates.latitude,
        longitude: contextCoordinates.longitude,
        radiusMiles: requestedRadius ?? DEFAULT_LOCAL_BUSINESS_RADIUS_MILES,
      },
    };
  }

  return {
    ...intent,
    location: {
      ...currentLocation,
      text: safeText(currentLocation.text || contextText, 80),
      latitude: null,
      longitude: null,
      radiusMiles: currentLocation.radiusMiles ?? null,
    },
  };
}

function normaliseIntent(value, query, now = new Date()) {
  const data = value && typeof value === "object" ? value : {};
  const deterministicActionIntent = inferActionIntent(query);
  let interpretedIntent = deterministicActionIntent || (INTENTS.has(data.intent)
    ? data.intent
    : inferIntent(query));
  if (ACTION_INTENTS.has(interpretedIntent) && hasDiscoveryCue(normaliseText(query))) {
    interpretedIntent = inferIntent(query);
  }
  const intent = interpretedIntent === "find_community_help" &&
    hasStructuralGroupIntent(query) &&
    !hasCommunityHelpIntent(query)
    ? "find_organisation"
    : interpretedIntent;
  const fallback = heuristicIntentWithoutNormalise(query, now);
  return {
    intent,
    searchText: safeText(data.searchText || fallback.searchText || query, 120),
    category: safeText(data.category, 80),
    serviceType: safeText(data.serviceType || fallback.serviceType, 80),
    dateRange: normaliseDateRange(data.dateRange) || fallback.dateRange,
    timeRange: normaliseTimeRange(data.timeRange) || fallback.timeRange,
    location: normaliseLocation(data.location, fallback.location),
    requiresAvailability: Boolean(data.requiresAvailability ?? fallback.requiresAvailability),
    allowDiscoveryFallback: Boolean(data.allowDiscoveryFallback ?? fallback.allowDiscoveryFallback),
    audience: safeText(data.audience || fallback.audience, 60),
    age: toNumber(data.age) ?? fallback.age,
    sort: ["soonest", "nearest", "relevance"].includes(data.sort) ? data.sort : fallback.sort,
    confidence: Math.max(0, Math.min(1, toNumber(data.confidence) ?? fallback.confidence)),
  };
}

function heuristicIntentWithoutNormalise(query, now) {
  const capped = safeText(query, MAX_QUERY_LENGTH);
  const lower = normaliseText(capped);
  const ageMatch = lower.match(/\b(\d{1,2})\s*(year old|yo|yrs? old)\b/);
  const radiusMatch = lower.match(/within\s+(\d{1,2})\s*miles?/);
  const intent = inferIntent(capped);
  return {
    intent,
    searchText: stripIntentWords(capped),
    serviceType: stripIntentWords(capped),
    dateRange: dateRangeFromQuery(capped, now),
    timeRange: timeRangeFromQuery(capped),
    location: {
      text: locationTextFromQuery(capped) || (lower.includes("burntwood") ? "Burntwood" : lower.includes("lichfield") ? "Lichfield" : ""),
      radiusMiles: radiusMatch ? Number(radiusMatch[1]) : null,
    },
    requiresAvailability: intent === "find_availability" || lower.includes("available") || lower.includes("cancellation"),
    allowDiscoveryFallback: intent === "find_availability" &&
      !/\b(available|availability|appointment|appointments|cancellation|cancellations|slot|slots)\b/.test(lower),
    audience: /child|children|year old|family/.test(lower) ? "children" : "",
    age: ageMatch ? Number(ageMatch[1]) : null,
    sort: intent === "find_availability" ? "soonest" : lower.includes("near") ? "nearest" : "relevance",
    confidence: intent === "unknown" ? 0.2 : 0.62,
  };
}

function parseModelIntentResponse(payload, query, now = new Date()) {
  const text = payload?.output?.[0]?.content?.[0]?.text || payload?.output_text;
  if (!text) throw new Error("Missing model output text.");
  return normaliseIntent(JSON.parse(text), query, now);
}

function intentSchema() {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      intent: { type: "string", enum: Array.from(INTENTS) },
      searchText: { type: "string" },
      category: { type: "string" },
      serviceType: { type: "string" },
      dateRange: {
        anyOf: [
          { type: "null" },
          {
            type: "object",
            additionalProperties: false,
            properties: {
              start: { type: "string" },
              end: { type: "string" },
            },
            required: ["start", "end"],
          },
        ],
      },
      timeRange: {
        anyOf: [
          { type: "null" },
          {
            type: "object",
            additionalProperties: false,
            properties: {
              start: { type: "string" },
              end: { type: "string" },
            },
            required: ["start", "end"],
          },
        ],
      },
      location: {
        type: "object",
        additionalProperties: false,
        properties: {
          text: { type: "string" },
          latitude: { anyOf: [{ type: "number" }, { type: "null" }] },
          longitude: { anyOf: [{ type: "number" }, { type: "null" }] },
          radiusMiles: { anyOf: [{ type: "number" }, { type: "null" }] },
        },
        required: ["text", "latitude", "longitude", "radiusMiles"],
      },
      requiresAvailability: { type: "boolean" },
      audience: { type: "string" },
      age: { anyOf: [{ type: "number" }, { type: "null" }] },
      sort: { type: "string", enum: ["soonest", "nearest", "relevance"] },
      confidence: { type: "number" },
    },
    required: [
      "intent",
      "searchText",
      "category",
      "serviceType",
      "dateRange",
      "timeRange",
      "location",
      "requiresAvailability",
      "audience",
      "age",
      "sort",
      "confidence",
    ],
  };
}

async function interpretWithOpenAI({ fetchImpl, query, context, now }) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured.");

  const response = await fetchImpl("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: ASK_MODEL,
      input: [
        {
          role: "system",
          content: [
            {
              type: "input_text",
              text:
                "You classify LocalLink local discovery requests. Return only strict JSON. " +
                "Do not invent businesses, results, routes, or Firestore queries. " +
      "Use find_* intents when the user is searching, including phrases like find, show, are there any, near me, available, or I need. " +
                "Community Challenges are a type of activity/opportunity, so challenge, competition, contest, prize, photo challenge, closing soon, and things the user can enter should use find_activity, not a separate intent. " +
                "Use action intents only when the user wants to create, report, add, list, or advertise something themselves. " +
                "Examples: 'I found some keys' is report_found_item; 'I lost my keys' is report_lost_item; 'my cat is missing' is report_missing_pet; 'are there any missing cats near me?' is find_community_help; 'I need a plumber' is find_service; 'I am a plumber and want to list my business' is list_business. " +
                `Use Europe/London dates. Today is ${dateKeyInLondon(now)}.`,
            },
          ],
        },
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify({
                query,
                context: {
                  locationText: safeText(context?.locationText, 80),
                  hasCoordinates: Boolean(context?.latitude && context?.longitude),
                },
              }),
            },
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "ask_locallink_intent",
          strict: true,
          schema: intentSchema(),
        },
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI intent request failed with ${response.status}.`);
  }
  return parseModelIntentResponse(await response.json(), query, now);
}

function fieldsText(...values) {
  return values.flatMap((value) => {
    if (Array.isArray(value)) return value;
    return [value];
  }).map(normaliseText).join(" ");
}

function textTokens(...values) {
  return fieldsText(...values)
    .split(/[^a-z0-9]+/)
    .map(normaliseSearchToken)
    .filter((token) => token.length > 0);
}

function editDistanceWithin(a, b, maxDistance) {
  if (a === b) return true;
  if (!a || !b) return false;
  if (Math.abs(a.length - b.length) > maxDistance) return false;

  const previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    const current = [i];
    let rowMin = current[0];
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      const value = Math.min(
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost
      );
      current[j] = value;
      rowMin = Math.min(rowMin, value);
    }
    if (rowMin > maxDistance) return false;
    previous.splice(0, previous.length, ...current);
  }
  return previous[b.length] <= maxDistance;
}

function tokenSimilarityThreshold(term) {
  if (term.length <= 3) return 0;
  if (term.length <= 5) return 1;
  return 2;
}

function tokenMatches(term, candidate) {
  if (!term || !candidate) return false;
  if (candidate.includes(term) || term.includes(candidate)) {
    return Math.min(term.length, candidate.length) >= 4 || term === candidate;
  }
  const maxDistance = tokenSimilarityThreshold(term);
  if (maxDistance === 0) return false;
  return editDistanceWithin(term, candidate, maxDistance);
}

function tokenLikeAny(text, vocabulary) {
  const tokens = textTokens(text);
  return tokens.some((token) =>
    vocabulary.some((word) => tokenMatches(normaliseSearchToken(word), token))
  );
}

function hasTokenMatchInValues(term, ...values) {
  return textTokens(...values).some((candidate) => tokenMatches(term, candidate));
}

function textMatches(data, terms) {
  const isChallenge = safeText(data.activityKind).toLowerCase() === "community_challenge";
  const haystack = fieldsText(
    data.title,
    data.name,
    data.businessName,
    data.serviceName,
    data.category,
    data.serviceCategory,
    data.organisationName,
    data.organisationCategory,
    data.subcategories,
    data.organisationSubcategories,
    data.activityType,
    data.audience,
    data.audienceValues,
    data.tags,
    data.activityKind,
    isChallenge ? "community challenge competition contest enter entry entries prize prizes win giveaway local challenge open closing soon ending soon" : "",
    isChallenge && data.allowPhotoEntries === true ? "photo picture" : "",
    data.prizeDescription,
    data.hostedByName,
    data.groupName,
    data.supportedByBusinessName,
    data.supportedByBusinessPrizeText,
    data.description,
    data.details,
    data.publicLocation,
    data.location,
    data.area,
    data.town,
    data.city,
    data.keywords,
    data.itemCategory,
    data.petType
  );
  const tokens = textTokens(haystack);
  return terms.every((term) =>
    haystack.includes(term) ||
    tokens.some((candidate) => tokenMatches(term, candidate))
  );
}

function locationTextMatches(data, intent) {
  const locationText = safeText(intent.location?.text, 80);
  if (!locationText) return true;
  const terms = textTokens(locationText).filter((term) => term.length > 2);
  if (!terms.length) return true;
  return terms.every((term) =>
    hasTokenMatchInValues(
      term,
      data.publicLocation,
      data.location,
      data.area,
      data.town,
      data.city,
      data.serviceArea
    )
  );
}

const ORGANISATION_GENERIC_TERMS = new Set([
  "group",
  "club",
  "organisation",
  "organization",
  "society",
]);

const LOCATION_CONNECTOR_TERMS = new Set([
  "around",
  "in",
  "near",
  "local",
]);

const DISCOVERY_STOP_TERMS = new Set([
  "any",
  "anything",
  "are",
  "can",
  "cut",
  "could",
  "find",
  "for",
  "got",
  "have",
  "me",
  "my",
  "locally",
  "looking",
  "need",
  "please",
  "some",
  "someone",
  "something",
  "space",
  "there",
  "thing",
  "things",
  "to",
  "what",
  "where",
  "with",
]);

const STRICT_SERVICE_TERMS = new Set([
  "cleaner",
  "cleaning",
  "decorator",
  "electrician",
  "gardener",
  "grass",
  "groomer",
  "grooming",
  "hairdresser",
  "heating",
  "lawn",
  "nail",
  "plumber",
  "plumbing",
  "service",
]);

const COMMUNITY_HELP_TERMS = new Set([
  "found",
  "free",
  "lost",
  "missing",
  "sighting",
]);

function searchTerms(intent, options = {}) {
  const locationTerms = new Set(
    normaliseText(intent.location?.text || "")
      .split(/\s+/)
      .filter((term) => term.length > 2)
  );
  return normaliseText([
    intent.searchText,
    intent.serviceType,
    intent.category,
  ].filter(Boolean).join(" "))
    .split(/[^a-z0-9]+/)
    .map(normaliseSearchToken)
    .filter((term) => term.length > 2)
    .filter((term) => !DISCOVERY_STOP_TERMS.has(term))
    .filter((term) => !LOCATION_CONNECTOR_TERMS.has(term))
    .filter((term) => !locationTerms.has(term))
    .filter((term) => !options.omitOrganisationGenericTerms || !ORGANISATION_GENERIC_TERMS.has(term))
    .slice(0, 6);
}

function meaningfulTerms(intent, options = {}) {
  return searchTerms(intent, options);
}

function isStrictServiceQuery(intent) {
  return meaningfulTerms(intent).some((term) => STRICT_SERVICE_TERMS.has(term));
}

function isCommunityHelpQuery(intent) {
  return meaningfulTerms(intent).some((term) => COMMUNITY_HELP_TERMS.has(term));
}

function mergeRankedResults(resultSets, intent) {
  const byKey = new Map();
  for (const results of resultSets) {
    for (const result of results) {
      const key = `${result.type}:${result.parentId || ""}:${result.id}`;
      if (!byKey.has(key)) byKey.set(key, result);
    }
  }
  return rankResults([...byKey.values()], intent).slice(0, 10);
}

function distanceMiles(aLat, aLng, bLat, bLng) {
  const lat1 = toNumber(aLat);
  const lng1 = toNumber(aLng);
  const lat2 = toNumber(bLat);
  const lng2 = toNumber(bLng);
  if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
  if (!isValidCoordinatePair(lat1, lng1) || !isValidCoordinatePair(lat2, lng2)) return null;
  const radians = (value) => value * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLng = radians(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLng / 2) ** 2;
  return 3958.8 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function distanceFor(data, intent) {
  return distanceMiles(
    intent.location?.latitude,
    intent.location?.longitude,
    data.latitude ?? data.approxLatitude,
    data.longitude ?? data.approxLongitude
  );
}

function withinRadius(data, intent) {
  const radius = intent.location?.radiusMiles;
  if (!radius) return true;
  const distance = distanceFor(data, intent);
  return distance != null && distance <= radius;
}

function communityHelpDiscoveryRadiusMiles(data) {
  const stored = toNumber(data.discoveryRadiusMiles);
  if (stored != null && stored > 0) return stored;
  return safeText(data.itemCategory).toLowerCase() === "pet"
    ? DEFAULT_PET_DISCOVERY_RADIUS_MILES
    : DEFAULT_COMMUNITY_HELP_DISCOVERY_RADIUS_MILES;
}

function communityHelpGeographicallyEligible(data, intent) {
  if (isValidCoordinatePair(intent.location?.latitude, intent.location?.longitude)) {
    const coordinates = require('./public_location').publicCommunityCoordinates(data);
    const distance = coordinates ? distanceFor(coordinates, intent) : null;
    return distance != null && distance <= communityHelpDiscoveryRadiusMiles(data);
  }

  const locationText = safeText(intent.location?.text, 80);
  if (!locationText) return false;
  return locationTextMatches(data, intent);
}

function sameDateKey(value, range) {
  if (!range) return true;
  const millis = timestampMillis(value);
  if (!millis) return false;
  const key = dateKeyInLondon(new Date(millis));
  return key >= range.start && key <= range.end;
}

function timeInRange(value, range) {
  if (!range) return true;
  const millis = timestampMillis(value);
  if (!millis) return false;
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date(millis));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const key = `${values.hour}:${values.minute}`;
  return key >= range.start && key <= range.end;
}

function activityTimeInRange(activity, range) {
  if (!range) return true;

  if (activity && Object.prototype.hasOwnProperty.call(activity, "eventTime")) {
    const eventTime = parseActivityEventTime(activity.eventTime);
    if (!eventTime) return false;
    return eventTime.label >= range.start && eventTime.label <= range.end;
  }

  const startValue = activity?.startTime;
  if (startValue && !isLondonMidnight(startValue)) {
    return timeInRange(startValue, range);
  }

  const dateValue = activity?.eventDate;
  if (dateValue && !isLondonMidnight(dateValue)) {
    return timeInRange(dateValue, range);
  }

  return false;
}

function isBusinessVisible(data) {
  return !hasPublicVisibilityBlock(data) &&
    data?.isActive !== false &&
    (data?.isClaimed === true ||
      (data?.createdByModerator === true &&
        data?.listingOwnershipStatus !== "claimed" &&
        data?.claimStatus !== "approved"));
}

function isBookableBusiness(data) {
  return isBusinessVisible(data);
}

function isServiceVisible(data) {
  return !hasPublicVisibilityBlock(data) &&
    data?.isActive !== false &&
    data?.isPublished !== false &&
    data?.isEnabled !== false &&
    data?.moderationStatus !== "removed" &&
    data?.approvalStatus !== "rejected";
}

function isAvailabilityVisible(data, now) {
  const endMillis = timestampMillis(data.endDateTime ?? data.endTime ?? data.availableUntil ?? data.availabilityAt);
  const status = safeText(data.status || "live").toLowerCase();
  return !hasPublicVisibilityBlock(data) &&
    data.isActive !== false &&
    !["booked", "expired", "cancelled", "closed"].includes(status) &&
    (!endMillis || endMillis > now.getTime());
}

function isCommunityHelpVisible(data, now) {
  const status = safeText(data.status || "active").toLowerCase();
  const expiresAt = timestampMillis(data.expiresAt);
  return !hasPublicVisibilityBlock(data) &&
    data.isActive !== false &&
    ["active", "open", "missing", "looking_for_owner"].includes(status) &&
    (!expiresAt || expiresAt > now.getTime());
}

function isPublicActivityVisible(data, now) {
  if (require('./discovery_privacy').activityDiscoveryVisibility(data) !== 'public') return false;
  const scope = safeText(data.activityAudienceScope || "everyone");
  const expiresAt = activityExpiresMillis(data);
  return !hasPublicVisibilityBlock(data) &&
    data.isActive !== false &&
    scope === "everyone" &&
    data.isPubliclyDiscoverable !== false &&
    (!expiresAt || expiresAt > now.getTime());
}

function isCommunityChallenge(activity) {
  return safeText(activity?.activityKind).toLowerCase() === "community_challenge";
}

function challengeClosesMillis(activity) {
  return timestampMillis(activity?.challengeClosesAt);
}

function activityExpiresMillis(activity) {
  if (isCommunityChallenge(activity)) {
    const closesAt = challengeClosesMillis(activity);
    if (closesAt) return closesAt;
  }

  const eventMillis = timestampMillis(activity?.eventDate);
  if (!eventMillis) return null;

  const event = new Date(eventMillis);
  const londonParts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(event);
  const parts = Object.fromEntries(londonParts.map((part) => [part.type, part.value]));
  const isDateOnly =
    parts.hour === "00" &&
    parts.minute === "00" &&
    parts.second === "00";
  if (!isDateOnly) return eventMillis;

  const nextDay = new Date(eventMillis);
  nextDay.setUTCDate(nextDay.getUTCDate() + 1);
  return nextDay.getTime();
}

function isChallengeOpenForEntry(activity, now) {
  const closesAt = challengeClosesMillis(activity);
  return !closesAt || closesAt >= now.getTime();
}

function challengeResultMetadata(activity, now) {
  if (!isCommunityChallenge(activity)) {
    return {};
  }

  const closesAt = challengeClosesMillis(activity);
  const prize = safeText(
    activity.prizeDescription || activity.supportedByBusinessPrizeText,
    120
  );
  const metadata = {
    activityKind: "community_challenge",
    isOpenForEntry: isChallengeOpenForEntry(activity, now),
  };

  if (closesAt) {
    metadata.challengeClosesAt = new Date(closesAt).toISOString();
  }
  if (prize) {
    metadata.prizeDescription = prize;
  }
  if (safeText(activity.businessName || activity.hostedByName || activity.organisationName || activity.groupName, 80)) {
    metadata.hostedByName = safeText(
      activity.businessName || activity.hostedByName || activity.organisationName || activity.groupName,
      80
    );
  }
  if (safeText(activity.supportedByBusinessName, 80)) {
    metadata.supportedByBusinessName = safeText(activity.supportedByBusinessName, 80);
  }

  return metadata;
}

function isDiscoverableOrganisation(data) {
  return !hasPublicVisibilityBlock(data) &&
    data.isActive !== false &&
    (
      data.claimStatus === "approved" ||
      data.listingOwnershipStatus === "claimed" ||
      data.createdByModerator === true
    );
}

function isDiscoverableGroup(data) {
  return !hasPublicVisibilityBlock(data) &&
    data.isActive !== false &&
    (
      data.visibility === "public" ||
      !Object.prototype.hasOwnProperty.call(data, "visibility")
    );
}

function hasPublicVisibilityBlock(data) {
  if (!data) return true;
  if (data.isDeleted === true || data.deleted === true) return true;
  if (data.archived === true || data.isArchived === true) return true;
  if (data.hidden === true || data.isHidden === true) return true;
  if (data.private === true || data.isPrivate === true) return true;
  if (data.isPubliclyDiscoverable === false) return true;

  const visibility = safeText(data.visibility).toLowerCase();
  if (["private", "restricted", "members", "members_only"].includes(visibility)) return true;

  const status = safeText(data.status).toLowerCase();
  if ([
    "inactive",
    "archived",
    "deleted",
    "removed",
    "rejected",
  ].includes(status)) return true;

  const moderationStatus = safeText(data.moderationStatus).toLowerCase();
  return [
    "removed",
    "rejected",
    "blocked",
    "hidden",
  ].includes(moderationStatus);
}

function routeFor(type, id, parentId = "") {
  const builder = RESULT_ROUTES[type];
  return builder ? builder({ id, parentId }) : "";
}

function makeResult({ type, id, parentId = "", title, subtitle = "", metadata = {}, data = {}, intent }) {
  const distance = distanceFor(data, intent);
  return {
    type,
    id,
    parentId,
    title: safeText(title || "LocalLink result", 100),
    subtitle: safeText(subtitle, 180),
    distanceMiles: distance == null ? null : Math.round(distance * 10) / 10,
    dateTime: safeText(metadata.dateTime, 40),
    route: routeFor(type, id, parentId),
    metadata,
  };
}

function makeActionResult(intent) {
  const definition = ACTION_DEFINITIONS[intent.intent];
  if (!definition) return null;

  const lower = normaliseText([
    intent.searchText,
    intent.serviceType,
    intent.category,
  ].filter(Boolean).join(" "));
  const metadata = {
    actionIntent: intent.intent,
    ...definition.metadata,
  };

  if (intent.intent === "report_missing_pet") {
    metadata.petType = petTypeFromQuery(lower);
  }
  if (intent.intent === "report_lost_item" || intent.intent === "report_found_item") {
    metadata.itemCategory = lostFoundCategoryFromQuery(lower);
  }
  if (intent.intent === "create_activity") {
    metadata.activityCategory = activityCategoryFromQuery(lower);
  }
  if (intent.intent === "list_business") {
    metadata.businessCategory = businessCategoryFromQuery(lower);
  }

  return makeResult({
    type: "action",
    id: intent.intent,
    title: definition.title,
    subtitle: definition.subtitle,
    metadata,
    intent,
  });
}

function rankResults(results, intent) {
  const challengeQuery = hasChallengeDiscoveryIntent(normaliseText([
    intent.searchText,
    intent.serviceType,
    intent.category,
  ].filter(Boolean).join(" ")));
  return [...results].sort((a, b) => {
    if (intent.sort === "soonest") {
      const aTime = Date.parse(a.dateTime || "");
      const bTime = Date.parse(b.dateTime || "");
      if (Number.isFinite(aTime) && Number.isFinite(bTime) && aTime !== bTime) return aTime - bTime;
    }
    if (challengeQuery) {
      const aChallenge = a.metadata?.activityKind === "community_challenge";
      const bChallenge = b.metadata?.activityKind === "community_challenge";
      if (aChallenge !== bChallenge) return aChallenge ? -1 : 1;
      if (aChallenge && bChallenge) {
        const aClosesAt = Date.parse(a.metadata?.challengeClosesAt || "");
        const bClosesAt = Date.parse(b.metadata?.challengeClosesAt || "");
        if (Number.isFinite(aClosesAt) && Number.isFinite(bClosesAt) && aClosesAt !== bClosesAt) {
          return aClosesAt - bClosesAt;
        }
      }
    }
    const aDistance = a.distanceMiles ?? 99999;
    const bDistance = b.distanceMiles ?? 99999;
    if (aDistance !== bDistance) return aDistance - bDistance;
    return a.title.localeCompare(b.title);
  }).slice(0, DEFAULT_LIMIT);
}

function rankScoredResults(scoredResults, intent) {
  return [...scoredResults].sort((a, b) => {
    if (a.sortMillis != null || b.sortMillis != null) {
      const aSort = a.sortMillis ?? Number.MAX_SAFE_INTEGER;
      const bSort = b.sortMillis ?? Number.MAX_SAFE_INTEGER;
      if (aSort !== bSort) return aSort - bSort;
    }

    const aScore = a.rankScore ?? 0;
    const bScore = b.rankScore ?? 0;
    if (aScore !== bScore) return bScore - aScore;

    if (intent.sort === "soonest") {
      const aTime = Date.parse(a.result.dateTime || "");
      const bTime = Date.parse(b.result.dateTime || "");
      if (Number.isFinite(aTime) && Number.isFinite(bTime) && aTime !== bTime) return aTime - bTime;
    }
    const aDistance = a.result.distanceMiles ?? 99999;
    const bDistance = b.result.distanceMiles ?? 99999;
    if (aDistance !== bDistance) return aDistance - bDistance;
    return a.result.title.localeCompare(b.result.title);
  }).slice(0, DEFAULT_LIMIT).map((item) => item.result);
}

function rankLocationAwareResults(scoredResults, intent, rankIntent = intent) {
  const hasLocationText = safeText(intent.location?.text, 80).length > 0;
  const preferred = hasLocationText && scoredResults.some((item) => item.locationMatch)
    ? scoredResults.filter((item) => item.locationMatch)
    : scoredResults;
  return rankScoredResults(preferred, rankIntent);
}

async function discoverServices(db, intent) {
  const terms = searchTerms(intent);
  const businesses = await db.collection("businesses")
    .where("isActive", "==", true)
    .limit(80)
    .get();
  const results = [];
  for (const businessDoc of businesses.docs) {
    const business = businessDoc.data() || {};
    if (!isBusinessVisible(business) || !withinRadius(business, intent)) continue;
    const businessLocationMatch = locationTextMatches(business, intent);
    const services = await businessDoc.ref.collection("services")
      .where("isActive", "==", true)
      .limit(20)
      .get();
    for (const serviceDoc of services.docs) {
      const service = {
        ...serviceDoc.data(),
        businessName: business.businessName || business.name,
        category: serviceDoc.data()?.category || business.category,
      };
      if (!isServiceVisible(service)) continue;
      if (terms.length && !textMatches({ ...business, ...service }, terms)) continue;
      results.push({
        locationMatch: businessLocationMatch,
        result: makeResult({
          type: "service",
          id: serviceDoc.id,
          parentId: businessDoc.id,
          title: service.name || service.serviceName,
          subtitle: [business.businessName || business.name, business.publicLocation || business.area].filter(Boolean).join(" · "),
          data: business,
          intent,
          metadata: { businessId: businessDoc.id, category: safeText(service.category || business.category) },
        }),
      });
    }
    if (!services.size && isBookableBusiness(business) && (!terms.length || textMatches(business, terms))) {
      results.push({
        locationMatch: businessLocationMatch,
        result: makeResult({
          type: "business",
          id: businessDoc.id,
          title: business.businessName || business.name,
          subtitle: [business.category, business.publicLocation || business.area].filter(Boolean).join(" · "),
          data: business,
          intent,
          metadata: { category: safeText(business.category) },
        }),
      });
    }
  }
  return rankLocationAwareResults(results, intent);
}

async function discoverAvailability(db, intent, now) {
  const terms = searchTerms(intent);
  const snap = await db.collection("availabilityPosts")
    .where("isActive", "==", true)
    .orderBy("availabilityAt", "asc")
    .limit(120)
    .get();
  const results = [];
  const businessCache = new Map();
  for (const doc of snap.docs) {
    const post = doc.data() || {};
    if (!isAvailabilityVisible(post, now)) continue;
    if (!sameDateKey(post.availabilityAt ?? post.startTime, intent.dateRange)) continue;
    if (!timeInRange(post.availabilityAt ?? post.startTime, intent.timeRange)) continue;
    const businessId = safeText(post.businessId);
    if (!businessId) continue;
    if (!businessCache.has(businessId)) {
      businessCache.set(businessId, (await db.collection("businesses").doc(businessId).get()).data() || null);
    }
    const business = businessCache.get(businessId);
    if (!business || !isBusinessVisible(business) || !withinRadius(business, intent)) continue;
    const locationMatch = locationTextMatches({ ...business, ...post }, intent);
    if (terms.length && !textMatches({ ...business, ...post }, terms)) continue;
    results.push({
      locationMatch,
      result: makeResult({
        type: "availability",
        id: doc.id,
        parentId: businessId,
        title: post.serviceName || post.title || "Available time",
        subtitle: [business.businessName || post.businessName, londonDateLabel(post.availabilityAt ?? post.startTime)].filter(Boolean).join(" · "),
        data: { ...business, ...post },
        intent,
        metadata: {
          businessId,
          serviceId: safeText(post.serviceId),
          dateTime: new Date(timestampMillis(post.availabilityAt ?? post.startTime) || Date.now()).toISOString(),
        },
      }),
    });
  }
  return rankLocationAwareResults(results, intent, { ...intent, sort: "soonest" });
}

async function discoverActivities(db, intent, now) {
  const terms = searchTerms(intent);
  const challengeQuery = hasChallengeDiscoveryIntent(normaliseText([
    intent.searchText,
    intent.serviceType,
    intent.category,
  ].filter(Boolean).join(" ")));
  const entryQuery = hasChallengeEntryIntent(intent);
  const closingSoonQuery = hasChallengeClosingSoonIntent(intent) ||
    terms.some((term) => ["closing", "ending", "soon", "open"].includes(term));
  const snap = await db.collection("opportunities")
    .where("isActive", "==", true)
    .limit(120)
    .get();
  const results = [];
  for (const doc of snap.docs) {
    const activity = doc.data() || {};
    const isChallenge = isCommunityChallenge(activity);
    if (!isPublicActivityVisible(activity, now)) continue;
    if (entryQuery && isChallenge && !isChallengeOpenForEntry(activity, now)) continue;
    if (closingSoonQuery && (!isChallenge || !isChallengeOpenForEntry(activity, now))) continue;
    if (!sameDateKey(activity.eventDate ?? activity.startTime, intent.dateRange)) continue;
    if (!activityTimeInRange(activity, intent.timeRange)) continue;
    if (intent.age != null) {
      const minAge = toNumber(activity.minimumAge ?? activity.ageMinimum);
      const maxAge = toNumber(activity.maximumAge ?? activity.ageMaximum);
      if (minAge != null && intent.age < minAge) continue;
      if (maxAge != null && intent.age > maxAge) continue;
    }
    if (!withinRadius(activity, intent)) continue;
    const locationMatch = locationTextMatches(activity, intent);
    if (terms.length && !textMatches(activity, terms)) continue;
    const closesAt = challengeClosesMillis(activity);
    results.push({
      locationMatch,
      rankScore: challengeQuery && isChallenge ? 1 : 0,
      sortMillis: challengeQuery && isChallenge ? closesAt : null,
      result: makeResult({
        type: "activity",
        id: doc.id,
        title: activity.title || activity.name,
        subtitle: [activityDateTimeLabel(activity), activity.publicLocation || activity.location].filter(Boolean).join(" · "),
        data: activity,
        intent,
        metadata: {
          category: safeText(activity.category),
          dateTime: activityResultDateTime(activity),
          ...challengeResultMetadata(activity, now),
        },
      }),
    });
  }
  return rankLocationAwareResults(results, intent);
}

async function discoverOrganisations(db, intent) {
  const terms = searchTerms(intent, { omitOrganisationGenericTerms: true });
  const snap = await db.collection("organisations")
    .limit(120)
    .get();
  const results = [];
  for (const doc of snap.docs) {
    const organisation = doc.data() || {};
    if (!isDiscoverableOrganisation(organisation)) {
      continue;
    }
    if (!withinRadius(organisation, intent)) continue;
    const organisationLocationMatch = locationTextMatches(organisation, intent);
    if (!terms.length || textMatches(organisation, terms)) {
      results.push({
        locationMatch: organisationLocationMatch,
        result: makeResult({
          type: "organisation",
          id: doc.id,
          title: organisation.name,
          subtitle: [organisation.category, organisation.publicLocation || organisation.area].filter(Boolean).join(" · "),
          data: organisation,
          intent,
          metadata: { category: safeText(organisation.category) },
        }),
      });
    }
    const groups = await doc.ref.collection("groups")
      .limit(40)
      .get();
    for (const groupDoc of groups.docs) {
      const group = groupDoc.data() || {};
      if (require('./discovery_privacy').groupDiscoveryVisibility(group) !== 'public') continue;
      if (!isDiscoverableGroup(group)) continue;
      const groupCategory = safeText(group.category || organisation.category);
      const groupSearchData = {
        ...organisation,
        ...group,
        organisationName: organisation.name,
        organisationCategory: organisation.category,
        category: groupCategory,
      };
      if (terms.length && !textMatches(groupSearchData, terms)) continue;
      results.push({
        locationMatch: organisationLocationMatch || locationTextMatches(groupSearchData, intent),
        result: makeResult({
          type: "group",
          id: groupDoc.id,
          parentId: doc.id,
          title: group.name,
          subtitle: [organisation.name, group.ageLabel || groupCategory].filter(Boolean).join(" · "),
          data: organisation,
          intent,
          metadata: { organisationId: doc.id, category: groupCategory },
        }),
      });
    }
  }
  return rankLocationAwareResults(results, intent);
}

async function discoverCommunityHelp(db, intent, now) {
  const terms = searchTerms(intent);
  const snap = await db.collection("communityHelpPosts")
    .where("isActive", "==", true)
    .limit(100)
    .get();
  const results = [];
  for (const doc of snap.docs) {
    const post = doc.data() || {};
    if (!isCommunityHelpVisible(post, now)) continue;
    if (!communityHelpGeographicallyEligible(post, intent)) continue;
    const locationMatch = locationTextMatches(post, intent);
    if (terms.length && !textMatches(post, terms)) continue;
    results.push({
      locationMatch,
      result: makeResult({
        type: "communityHelp",
        id: doc.id,
        title: post.title || "Community Help post",
        subtitle: [post.itemCategory || post.type, post.publicLocation || post.area].filter(Boolean).join(" · "),
        data: require('./public_location').publicCommunityCoordinates(post) || {},
        intent,
        metadata: { mode: safeText(post.mode), itemCategory: safeText(post.itemCategory) },
      }),
    });
  }
  return rankLocationAwareResults(results, intent);
}

async function discoverAskLocalLinkResults(db, intent, now = new Date()) {
  const activityAndOrganisation = async () => mergeRankedResults([
    await discoverActivities(db, intent, now),
    await discoverOrganisations(db, intent),
  ], intent);

  if (ACTION_INTENTS.has(intent.intent)) {
    const action = makeActionResult(intent);
    return action ? [action] : [];
  }

  switch (intent.intent) {
    case "find_service":
      {
        const services = await discoverServices(db, intent);
        if (services.length || isStrictServiceQuery(intent)) return services;
        return activityAndOrganisation();
      }
    case "find_availability":
      {
        const availability = await discoverAvailability(db, intent, now);
        if (availability.length) return availability;
        if (!intent.allowDiscoveryFallback) return [];
        const services = await discoverServices(db, { ...intent, sort: "relevance" });
        if (services.length && isStrictServiceQuery(intent)) return services;
        return mergeRankedResults([
          services,
          await discoverActivities(db, intent, now),
          await discoverOrganisations(db, intent),
        ], intent);
      }
    case "find_activity":
      return activityAndOrganisation();
    case "find_organisation":
      return activityAndOrganisation();
    case "find_community_help":
      return discoverCommunityHelp(db, intent, now);
    default:
      if (isCommunityHelpQuery(intent)) {
        return discoverCommunityHelp(db, intent, now);
      }
      return [];
  }
}

function buildAskLocalLinkExports({ admin, onCall, HttpsError, logger, fetchImpl = fetch }) {
  const firestore = admin.firestore();

  return {
    askLocalLink: onCall(
      {
        preserveExternalChanges: true,
        region: "us-central1",
        secrets: ["OPENAI_API_KEY"],
        timeoutSeconds: 30,
        memory: "512MiB",
      },
      async (request) => {
        const now = new Date();
        const query = safeText(request.data?.query, MAX_QUERY_LENGTH);
        if (!query) {
          throw new HttpsError("invalid-argument", "Enter something to search for.");
        }

        const context = request.data?.context && typeof request.data.context === "object"
          ? request.data.context
          : {};

        let intent;
        let usedFallback = false;
        try {
          intent = await interpretWithOpenAI({ fetchImpl, query, context, now });
        } catch (error) {
          usedFallback = true;
          logger.warn("Ask LocalLink intent interpretation failed; using safe fallback.", {
            message: safeText(error?.message, 120),
          });
          intent = heuristicIntent(query, now);
        }

        intent = applyAuthoritativeLocation(intent, { context });

        logger.info("Ask LocalLink interpreted intent.", {
          intent: intent.intent,
          confidence: intent.confidence,
          usedFallback,
          hasLocation: Boolean(intent.location.latitude && intent.location.longitude),
        });

        if (intent.intent === "unknown") {
          return { intent, results: [], status: "unknown" };
        }

        const results = await discoverAskLocalLinkResults(firestore, intent, now);
        logger.info("Ask LocalLink discovery completed.", {
          intent: intent.intent,
          resultCount: results.length,
        });
        return {
          intent,
          results,
          status: results.length ? "ok" : "no_results",
        };
      }
    ),
  };
}

module.exports = {
  buildAskLocalLinkExports,
  dateRangeFromQuery,
  discoverAskLocalLinkResults,
  heuristicIntent,
  normaliseIntent,
  parseModelIntentResponse,
  timeRangeFromQuery,
  applyAuthoritativeLocation,
  _private: {
    dateKeyInLondon,
    isValidCoordinatePair,
    isPublicActivityVisible,
    isCommunityHelpVisible,
    isAvailabilityVisible,
    textMatches,
  },
};
