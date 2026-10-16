"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  discoverAskLocalLinkResults,
  heuristicIntent,
  normaliseIntent,
  parseModelIntentResponse,
  applyAuthoritativeLocation,
  _private,
} = require("../ask_locallink");

const now = new Date("2026-09-15T12:00:00Z");

test("Ask LocalLink heuristic recognises approved phase 1 examples", () => {
  assert.equal(heuristicIntent("dog groomer tomorrow", now).intent, "find_availability");
  assert.equal(
    heuristicIntent("hairdresser available this afternoon", now).intent,
    "find_availability"
  );
  const ovenCleaner = heuristicIntent("oven cleaner within 5 miles", now);
  assert.equal(ovenCleaner.intent, "find_service");
  assert.equal(ovenCleaner.location.radiusMiles, 5);

  const childActivity = heuristicIntent("anything for my 5 year old Saturday morning?", now);
  assert.equal(childActivity.intent, "find_activity");
  assert.equal(childActivity.age, 5);
  assert.deepEqual(childActivity.timeRange, { start: "06:00", end: "12:00" });

  assert.equal(heuristicIntent("football clubs near me", now).intent, "find_organisation");
  assert.equal(heuristicIntent("any missing dogs nearby?", now).intent, "find_community_help");
  assert.equal(heuristicIntent("hello", now).intent, "unknown");
});

test("Ask LocalLink heuristic separates action intents from discovery searches", () => {
  assert.equal(heuristicIntent("my cat is missing", now).intent, "report_missing_pet");
  assert.equal(heuristicIntent("I've lost my dog", now).intent, "report_missing_pet");
  assert.equal(heuristicIntent("My dog has got out", now).intent, "report_missing_pet");
  assert.equal(heuristicIntent("Our rabbit escaped", now).intent, "report_missing_pet");
  assert.equal(heuristicIntent("I lost my keys", now).intent, "report_lost_item");
  assert.equal(heuristicIntent("I've misplaced my wallet", now).intent, "report_lost_item");
  assert.equal(heuristicIntent("I found some keys", now).intent, "report_found_item");
  assert.equal(heuristicIntent("We have found a phone", now).intent, "report_found_item");
  assert.equal(heuristicIntent("I am giving away a sofa", now).intent, "give_away_item");
  assert.equal(heuristicIntent("I have a sofa to give away", now).intent, "give_away_item");
  assert.equal(
    heuristicIntent("I run a dance class and want to add it", now).intent,
    "create_activity"
  );
  assert.equal(
    heuristicIntent("I want to add my running group", now).intent,
    "create_activity"
  );
  assert.equal(
    heuristicIntent("I am a plumber and want to list my business", now).intent,
    "list_business"
  );
  assert.equal(
    heuristicIntent("Can I put my cleaning business on here?", now).intent,
    "list_business"
  );
  assert.equal(heuristicIntent("Are there any missing cats near me?", now).intent, "find_community_help");
  assert.equal(heuristicIntent("Has anyone lost a dog?", now).intent, "find_community_help");
  assert.equal(heuristicIntent("I need a plumber", now).intent, "find_service");
  assert.equal(heuristicIntent("Who's a good cleaner near me?", now).intent, "find_service");
  assert.equal(heuristicIntent("Find a dance class", now).intent, "find_activity");
  assert.equal(heuristicIntent("Are there hair appointments today?", now).intent, "find_availability");
});

test("Ask LocalLink heuristic recognises community challenge searches as activities", () => {
  for (const query of [
    "Are there any community challenges near me?",
    "Any competitions I can enter?",
    "Are there any photo competitions?",
    "Anything I can enter with my dog?",
    "Any dog challenges?",
    "Can I win anything locally?",
    "Any competitions still open?",
    "What's closing soon?",
    "Show me local challenges",
    "Is there anything for families to enter?",
  ]) {
    assert.equal(heuristicIntent(query, now).intent, "find_activity", query);
  }

  assert.equal(heuristicIntent("Things to do with the kids this weekend", now).intent, "find_activity");
  assert.equal(heuristicIntent("I need a plumber", now).intent, "find_service");
});

test("Ask LocalLink normalisation lets strong action signals override model search or unknown intents", () => {
  assert.equal(
    normaliseIntent(
      { intent: "find_service", searchText: "lost dog" },
      "I've lost my dog",
      now
    ).intent,
    "report_missing_pet"
  );
  assert.equal(
    normaliseIntent(
      { intent: "find_community_help", searchText: "cat missing" },
      "My cat is missing",
      now
    ).intent,
    "report_missing_pet"
  );
  assert.equal(
    normaliseIntent(
      { intent: "unknown", searchText: "found keys" },
      "I found some keys",
      now
    ).intent,
    "report_found_item"
  );
  assert.equal(
    normaliseIntent(
      { intent: "unknown", searchText: "dance class" },
      "I run a dance class and want to add it",
      now
    ).intent,
    "create_activity"
  );
});

test("Ask LocalLink returns single safe action results with prefill metadata", async () => {
  const foundIntent = heuristicIntent("I found some keys", now);
  const results = await discoverAskLocalLinkResults(fakeDb({}), foundIntent, now);

  assert.equal(results.length, 1);
  assert.equal(results[0].type, "action");
  assert.equal(results[0].id, "report_found_item");
  assert.equal(results[0].metadata.actionIntent, "report_found_item");
  assert.equal(results[0].metadata.communityHelpType, "lost_found");
  assert.equal(results[0].metadata.mode, "found");
  assert.equal(results[0].metadata.itemCategory, "Keys");

  const missingPetResults = await discoverAskLocalLinkResults(
    fakeDb({}),
    heuristicIntent("My cat is missing", now),
    now
  );
  assert.equal(missingPetResults[0].id, "report_missing_pet");
  assert.equal(missingPetResults[0].metadata.itemCategory, "Pet");
  assert.equal(missingPetResults[0].metadata.petType, "cat");
});

test("model action classifications are guarded when the query is a search", () => {
  assert.equal(
    normaliseIntent(
      { intent: "report_missing_pet", searchText: "missing cats" },
      "Are there any missing cats near me?",
      now
    ).intent,
    "find_community_help"
  );
  assert.equal(
    normaliseIntent(
      { intent: "list_business", searchText: "plumber" },
      "I need a plumber",
      now
    ).intent,
    "find_service"
  );
});

test("normalises strict model output and rejects arbitrary intent names", () => {
  const intent = parseModelIntentResponse({
    output: [{
      content: [{
        text: JSON.stringify({
          intent: "made_up_query",
          searchText: "dog groomer",
          category: "",
          serviceType: "dog grooming",
          dateRange: { start: "2026-09-16", end: "2026-09-16" },
          timeRange: null,
          location: { text: "Burntwood", latitude: null, longitude: null, radiusMiles: null },
          requiresAvailability: true,
          audience: "",
          age: null,
          sort: "soonest",
          confidence: 0.9,
        }),
      }],
    }],
  }, "dog groomer tomorrow", now);

  assert.equal(intent.intent, "find_availability");
  assert.equal(intent.dateRange.start, "2026-09-16");
  assert.equal(intent.serviceType, "dog grooming");
});

test("normalises generic group queries away from accidental Community Help routing", () => {
  assert.equal(
    normaliseIntent(
      { intent: "find_community_help", searchText: "a group in Burntwood" },
      "a group in Burntwood",
      now
    ).intent,
    "find_organisation"
  );
  assert.equal(
    normaliseIntent(
      { intent: "find_community_help", searchText: "groups near me" },
      "groups near me",
      now
    ).intent,
    "find_organisation"
  );
  assert.equal(
    normaliseIntent(
      { intent: "find_community_help", searchText: "a club in Burntwood" },
      "a club in Burntwood",
      now
    ).intent,
    "find_organisation"
  );
  assert.equal(
    normaliseIntent(
      { intent: "find_community_help", searchText: "lost dog" },
      "lost dog",
      now
    ).intent,
    "find_community_help"
  );
  assert.equal(
    normaliseIntent(
      { intent: "find_community_help", searchText: "found keys" },
      "found keys",
      now
    ).intent,
    "find_community_help"
  );
});

test("Ask distance uses supplied authoritative discovery coordinates", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("little-friends", {
        isActive: true,
        title: "Little Friends baby and toddler group",
        category: "Children & Family",
        description: "Friendly sessions for babies and toddlers",
        publicLocation: "Burntwood",
        latitude: 52.681,
        longitude: -1.908,
        eventDate: fakeTimestamp("2026-09-23T09:30:00Z"),
      }),
    ],
  });

  const intent = applyAuthoritativeLocation(
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      serviceType: "baby",
      location: {
        text: "Burntwood",
        latitude: 0,
        longitude: 0,
        radiusMiles: null,
      },
    }, "a baby group in Burntwood", now),
    {
      context: {
        locationText: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
      },
    }
  );

  const results = await discoverAskLocalLinkResults(db, intent, now);

  assert.deepEqual(results.map((result) => result.id), ["little-friends"]);
  assert.ok(results[0].distanceMiles > 0);
  assert.ok(results[0].distanceMiles < 2);
});

test("explicit place search does not use unrelated default coordinates", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("little-friends", {
        isActive: true,
        title: "Little Friends baby and toddler group",
        category: "Children & Family",
        description: "Friendly sessions for babies and toddlers",
        publicLocation: "Burntwood",
        latitude: 52.681,
        longitude: -1.908,
        eventDate: fakeTimestamp("2026-09-23T09:30:00Z"),
      }),
    ],
  });

  const intent = applyAuthoritativeLocation(
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      serviceType: "baby",
      location: {
        text: "Burntwood",
        latitude: 0,
        longitude: 0,
        radiusMiles: null,
      },
    }, "a baby group in Burntwood", now),
    { context: {} }
  );

  const results = await discoverAskLocalLinkResults(db, intent, now);

  assert.deepEqual(results.map((result) => result.id), ["little-friends"]);
  assert.equal(results[0].distanceMiles, null);
});

test("near-me query uses existing LocalLink discovery location when available", async () => {
  const intent = applyAuthoritativeLocation(
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby groups near me",
      location: { text: "", radiusMiles: 5 },
    }, "baby groups near me", now),
    {
      context: {
        latitude: 52.681,
        longitude: -1.927,
      },
    }
  );

  assert.equal(intent.location.latitude, 52.681);
  assert.equal(intent.location.longitude, -1.927);
  assert.equal(intent.location.radiusMiles, 5);
});

test("Ask service discovery applies default local radius when coordinates are available", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("local-plumber", {
        isActive: true,
        isClaimed: true,
        businessName: "Local Plumbing",
        category: "Plumber",
        publicLocation: "Burntwood",
        latitude: 52.690,
        longitude: -1.920,
      }, {
        services: [
          fakeDoc("local-service", {
            isActive: true,
            isPublished: true,
            name: "Plumbing repairs",
            details: "Local plumbing help",
          }),
        ],
      }),
      fakeDoc("far-plumber", {
        isActive: true,
        isClaimed: true,
        businessName: "Far Plumbing",
        category: "Plumber",
        publicLocation: "London",
        latitude: 51.5072,
        longitude: -0.1276,
      }, {
        services: [
          fakeDoc("far-service", {
            isActive: true,
            isPublished: true,
            name: "Plumbing repairs",
            details: "Distant plumbing help",
          }),
        ],
      }),
      fakeDoc("missing-coordinates", {
        isActive: true,
        isClaimed: true,
        businessName: "No Coordinates Plumbing",
        category: "Plumber",
        publicLocation: "Burntwood",
      }, {
        services: [
          fakeDoc("missing-service", {
            isActive: true,
            isPublished: true,
            name: "Plumbing repairs",
          }),
        ],
      }),
    ],
  });

  const query = "I need a plumber";
  const intent = applyAuthoritativeLocation(
    normaliseIntent(heuristicIntent(query, now), query, now),
    {
      context: {
        locationText: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
      },
    }
  );

  assert.equal(intent.location.radiusMiles, 40);

  const results = await discoverAskLocalLinkResults(db, intent, now);

  assert.deepEqual(results.map((result) => result.id), ["local-service"]);
});

test("Ask named-location service searches are not restricted to current coordinates", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("burntwood-plumber", {
        isActive: true,
        isClaimed: true,
        businessName: "Burntwood Plumbing",
        category: "Plumber",
        publicLocation: "Burntwood",
      }),
      fakeDoc("birmingham-plumber", {
        isActive: true,
        isClaimed: true,
        businessName: "Birmingham Plumbing",
        category: "Plumber",
        publicLocation: "Birmingham",
      }),
    ],
  });

  const query = "plumbers in Birmingham";
  const intent = applyAuthoritativeLocation(
    normaliseIntent(heuristicIntent(query, now), query, now),
    {
      context: {
        locationText: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
      },
    }
  );

  assert.equal(intent.location.text, "Birmingham");
  assert.equal(intent.location.latitude, null);
  assert.equal(intent.location.longitude, null);
  assert.equal(intent.location.radiusMiles, null);

  const results = await discoverAskLocalLinkResults(db, intent, now);

  assert.deepEqual(results.map((result) => result.id), ["birmingham-plumber"]);
});

test("missing, invalid or mismatched origins omit distance", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("little-friends", {
        isActive: true,
        title: "Little Friends baby and toddler group",
        category: "Children & Family",
        description: "Friendly sessions for babies and toddlers",
        publicLocation: "Burntwood",
        latitude: 52.681,
        longitude: -1.908,
        eventDate: fakeTimestamp("2026-09-23T09:30:00Z"),
      }),
    ],
  });

  for (const context of [
    {},
    { latitude: 0, longitude: 0 },
    { latitude: 181, longitude: -1.927 },
    { locationText: "Lichfield", latitude: 52.681, longitude: -1.927 },
  ]) {
    const intent = applyAuthoritativeLocation(
      normaliseIntent({
        intent: "find_activity",
        searchText: "baby",
        serviceType: "baby",
        location: { text: "Burntwood", radiusMiles: null },
      }, "a baby group in Burntwood", now),
      { context }
    );
    const results = await discoverAskLocalLinkResults(db, intent, now);
    assert.equal(results[0].distanceMiles, null);
  }
});

test("discovery maps service intent to existing business service entities", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("business-1", {
        isActive: true,
        isClaimed: true,
        chargesEnabled: true,
        businessName: "Burntwood Pets",
        category: "Dog Groomer",
        publicLocation: "Burntwood",
      }, {
        services: [
          fakeDoc("service-1", {
            isActive: true,
            isPublished: true,
            name: "Dog grooming",
            details: "Bath and tidy",
          }),
        ],
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_service", searchText: "dog groomer" }, "dog groomer", now),
    now
  );

  assert.equal(results.length, 1);
  assert.equal(results[0].type, "service");
  assert.equal(results[0].id, "service-1");
  assert.equal(results[0].parentId, "business-1");
});

test("service discovery can return claimed listing before payments are configured", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("business-1", {
        isActive: true,
        isClaimed: true,
        businessName: "Burntwood Garden Care",
        category: "Gardener",
        publicLocation: "Burntwood",
        paymentMethods: [],
        stripeChargesEnabled: false,
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_service", searchText: "gardener" }, "gardener", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["business-1"]);
  assert.equal(results[0].type, "business");
});

test("service discovery can return moderator seeded unclaimed business by name", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("teds-bakery-van", {
        isActive: true,
        isClaimed: false,
        createdByModerator: true,
        listingOwnershipStatus: "unclaimed",
        claimStatus: "unclaimed",
        businessOwnerId: "",
        ownerId: "",
        businessName: "Tedsbakeryvan",
        name: "Tedsbakeryvan",
        category: "Specialist Services",
        publicLocation: "Lichfield",
        latitude: 52.681602,
        longitude: -1.831672,
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_service",
      searchText: "Tedsbakeryvan",
      location: {
        text: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
        radiusMiles: 40,
      },
    }, "Tedsbakeryvan", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["teds-bakery-van"]);
  assert.equal(results[0].type, "business");
});

test("service discovery keeps seeded businesses local and public", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("local-seeded", {
        isActive: true,
        isClaimed: false,
        createdByModerator: true,
        listingOwnershipStatus: "unclaimed",
        claimStatus: "unclaimed",
        businessName: "Local Bakery Van",
        category: "Bakery",
        publicLocation: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
      }),
      fakeDoc("far-seeded", {
        isActive: true,
        isClaimed: false,
        createdByModerator: true,
        listingOwnershipStatus: "unclaimed",
        claimStatus: "unclaimed",
        businessName: "Far Bakery Van",
        category: "Bakery",
        publicLocation: "London",
        latitude: 51.5072,
        longitude: -0.1276,
      }),
      fakeDoc("hidden-seeded", {
        isActive: true,
        hidden: true,
        isClaimed: false,
        createdByModerator: true,
        listingOwnershipStatus: "unclaimed",
        claimStatus: "unclaimed",
        businessName: "Hidden Bakery Van",
        category: "Bakery",
        publicLocation: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_service",
      searchText: "bakery",
      location: {
        text: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
        radiusMiles: 15,
      },
    }, "bakery in Burntwood", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["local-seeded"]);
});

test("service discovery excludes inactive archived and private businesses", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("inactive-business", {
        isActive: false,
        isClaimed: true,
        businessName: "Inactive Garden Care",
        category: "Gardener",
        publicLocation: "Burntwood",
      }),
      fakeDoc("archived-business", {
        isActive: true,
        archived: true,
        isClaimed: true,
        businessName: "Archived Garden Care",
        category: "Gardener",
        publicLocation: "Burntwood",
      }),
      fakeDoc("private-business", {
        isActive: true,
        isPrivate: true,
        isClaimed: true,
        businessName: "Private Garden Care",
        category: "Gardener",
        publicLocation: "Burntwood",
      }),
      fakeDoc("visible-business", {
        isActive: true,
        isClaimed: true,
        businessName: "Visible Garden Care",
        category: "Gardener",
        publicLocation: "Burntwood",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_service", searchText: "gardener" }, "gardener", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["visible-business"]);
});

test("availability discovery only returns genuine active matching availability", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("business-1", {
        isActive: true,
        isClaimed: true,
        businessName: "Town Hair",
        category: "Hairdresser",
        publicLocation: "Burntwood",
      }),
    ],
    availabilityPosts: [
      fakeDoc("slot-1", {
        isActive: true,
        status: "live",
        businessId: "business-1",
        serviceId: "service-1",
        serviceName: "Haircut",
        availabilityAt: fakeTimestamp("2026-09-15T14:00:00Z"),
        endTime: fakeTimestamp("2026-09-15T15:00:00Z"),
      }),
      fakeDoc("slot-2", {
        isActive: true,
        status: "booked",
        businessId: "business-1",
        serviceName: "Haircut",
        availabilityAt: fakeTimestamp("2026-09-15T16:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_availability",
      searchText: "hairdresser",
      dateRange: { start: "2026-09-15", end: "2026-09-15" },
      timeRange: { start: "12:00", end: "17:00" },
    }, "hairdresser available this afternoon", now),
    now
  );

  assert.equal(results.length, 1);
  assert.equal(results[0].type, "availability");
  assert.equal(results[0].id, "slot-1");
});

test("availability discovery excludes archived expired and private records", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("business-1", {
        isActive: true,
        isClaimed: true,
        businessName: "Town Hair",
        category: "Hairdresser",
        publicLocation: "Burntwood",
      }),
    ],
    availabilityPosts: [
      fakeDoc("archived-slot", {
        isActive: true,
        archived: true,
        status: "live",
        businessId: "business-1",
        serviceName: "Haircut",
        availabilityAt: fakeTimestamp("2026-09-15T14:00:00Z"),
      }),
      fakeDoc("private-slot", {
        isActive: true,
        isPrivate: true,
        status: "live",
        businessId: "business-1",
        serviceName: "Haircut",
        availabilityAt: fakeTimestamp("2026-09-15T15:00:00Z"),
      }),
      fakeDoc("expired-slot", {
        isActive: true,
        status: "live",
        businessId: "business-1",
        serviceName: "Haircut",
        availabilityAt: fakeTimestamp("2026-09-15T09:00:00Z"),
        endTime: fakeTimestamp("2026-09-15T10:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_availability",
      searchText: "hairdresser",
      dateRange: { start: "2026-09-15", end: "2026-09-15" },
    }, "hairdresser available today", now),
    now
  );

  assert.deepEqual(results, []);
});

test("activity discovery omits private organisation and group activity", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("public-activity", {
        isActive: true,
        isPubliclyDiscoverable: true,
        activityAudienceScope: "everyone",
        title: "Saturday football",
        category: "Fitness & Sport",
        eventDate: fakeTimestamp("2026-09-19T09:30:00Z"),
      }),
      fakeDoc("private-group", {
        isActive: true,
        isPubliclyDiscoverable: true,
        activityAudienceScope: "group",
        title: "Private team training",
        category: "Fitness & Sport",
        eventDate: fakeTimestamp("2026-09-19T09:30:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "football",
      dateRange: { start: "2026-09-19", end: "2026-09-19" },
    }, "football Saturday", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["public-activity"]);
});

test("activity discovery keeps legacy public records and excludes explicit private records", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("legacy-public", {
        isActive: true,
        title: "Camera walk",
        category: "Photography",
        eventDate: fakeTimestamp("2026-09-19T09:30:00Z"),
      }),
      fakeDoc("explicit-hidden", {
        isActive: true,
        isPubliclyDiscoverable: false,
        activityAudienceScope: "everyone",
        title: "Camera committee",
        category: "Photography",
        eventDate: fakeTimestamp("2026-09-19T09:30:00Z"),
      }),
      fakeDoc("group-only", {
        isActive: true,
        isPubliclyDiscoverable: false,
        activityAudienceScope: "group",
        title: "Camera members session",
        category: "Photography",
        eventDate: fakeTimestamp("2026-09-19T09:30:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_activity", searchText: "camera" }, "camera", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["legacy-public"]);
});

test("activity discovery keeps date-only activities visible for their whole day", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("today", {
        isActive: true,
        title: "Today local activity",
        eventDate: fakeTimestamp("2026-09-14T23:00:00Z"),
      }),
      fakeDoc("yesterday", {
        isActive: true,
        title: "Yesterday local activity",
        eventDate: fakeTimestamp("2026-09-13T23:00:00Z"),
      }),
      fakeDoc("tomorrow", {
        isActive: true,
        title: "Tomorrow local activity",
        eventDate: fakeTimestamp("2026-09-15T23:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_activity", searchText: "" }, "", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["today", "tomorrow"]);
});

test("Ask activity visibility matches Home blockers for private and moderated activities", () => {
  const activity = {
    isActive: true,
    title: "Community run",
    eventDate: fakeTimestamp("2026-09-16T10:00:00Z"),
  };

  assert.equal(_private.isPublicActivityVisible(activity, now), true);

  for (const blocker of [
    { private: true },
    { visibility: "private" },
    { status: "removed" },
    { status: "rejected" },
    { moderationStatus: "removed" },
    { moderationStatus: "rejected" },
    { moderationStatus: "blocked" },
    { moderationStatus: "hidden" },
  ]) {
    assert.equal(
      _private.isPublicActivityVisible({ ...activity, ...blocker }, now),
      false
    );
  }
});

test("challenge discovery uses challenge close time before event date fallback", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("open-today", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Today photo challenge",
        tags: ["Community challenge", "Photography"],
        eventDate: fakeTimestamp("2026-09-14T23:00:00Z"),
        challengeClosesAt: fakeTimestamp("2026-09-15T18:00:00Z"),
      }),
      fakeDoc("expired-close", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Expired photo challenge",
        tags: ["Community challenge", "Photography"],
        eventDate: fakeTimestamp("2026-09-19T23:00:00Z"),
        challengeClosesAt: fakeTimestamp("2026-09-15T09:00:00Z"),
      }),
      fakeDoc("fallback-today", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Fallback photo challenge",
        tags: ["Community challenge", "Photography"],
        eventDate: fakeTimestamp("2026-09-14T23:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("photo competitions", now), "photo competitions", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["fallback-today", "open-today"]);
});

test("activity discovery returns open community challenges with challenge metadata", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("dog-challenge", {
        isActive: true,
        isPubliclyDiscoverable: true,
        activityAudienceScope: "everyone",
        activityKind: "community_challenge",
        title: "Funniest Dog in Burntwood",
        category: "Pets",
        tags: ["Community challenge", "Dogs"],
        description: "Enter a funny dog photo",
        publicLocation: "Burntwood",
        challengeClosesAt: fakeTimestamp("2026-09-20T18:00:00Z"),
        allowPhotoEntries: true,
        prizeDescription: "£25 grooming voucher",
        supportedByBusinessName: "Burntwood Pets",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("Anything I can enter with my dog?", now), "Anything I can enter with my dog?", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["dog-challenge"]);
  assert.equal(results[0].type, "activity");
  assert.equal(results[0].route, "/opportunities/dog-challenge");
  assert.equal(results[0].metadata.activityKind, "community_challenge");
  assert.equal(results[0].metadata.isOpenForEntry, true);
  assert.equal(results[0].metadata.prizeDescription, "£25 grooming voucher");
  assert.equal(results[0].metadata.supportedByBusinessName, "Burntwood Pets");
  assert.equal(results[0].metadata.challengeClosesAt, "2026-09-20T18:00:00.000Z");
});

test("challenge discovery excludes closed entry-style and removed moderated challenges", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("open-challenge", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Local Photo Competition",
        tags: ["Community challenge", "Photography"],
        challengeClosesAt: fakeTimestamp("2026-09-20T18:00:00Z"),
        allowPhotoEntries: true,
      }),
      fakeDoc("closed-challenge", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Closed Photo Competition",
        tags: ["Community challenge", "Photography"],
        challengeClosesAt: fakeTimestamp("2026-09-10T18:00:00Z"),
        allowPhotoEntries: true,
      }),
      fakeDoc("removed-challenge", {
        isActive: true,
        moderationStatus: "removed",
        activityKind: "community_challenge",
        title: "Removed Photo Competition",
        tags: ["Community challenge", "Photography"],
        challengeClosesAt: fakeTimestamp("2026-09-20T18:00:00Z"),
        allowPhotoEntries: true,
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("Are there any photo competitions?", now), "Are there any photo competitions?", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["open-challenge"]);
});

test("closing soon challenge queries prefer the nearest open closing date", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("later", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Later local challenge",
        tags: ["Community challenge"],
        challengeClosesAt: fakeTimestamp("2026-09-25T18:00:00Z"),
      }),
      fakeDoc("soon", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Soon local challenge",
        tags: ["Community challenge"],
        challengeClosesAt: fakeTimestamp("2026-09-16T18:00:00Z"),
      }),
      fakeDoc("activity", {
        isActive: true,
        title: "Closing ceremony activity",
        description: "An ordinary activity mentioning closing soon",
        eventDate: fakeTimestamp("2026-09-20T10:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("What's closing soon?", now), "What's closing soon?", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["soon", "later"]);
});

test("challenge ranking boosts relevant challenges without suppressing matching normal activities", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("dog-walk", {
        isActive: true,
        title: "Dog walking social",
        category: "Pets",
        description: "A friendly activity for dog owners",
        eventDate: fakeTimestamp("2026-09-19T10:00:00Z"),
      }),
      fakeDoc("dog-challenge", {
        isActive: true,
        activityKind: "community_challenge",
        title: "Dog photo challenge",
        tags: ["Community challenge", "Dog"],
        challengeClosesAt: fakeTimestamp("2026-09-20T18:00:00Z"),
        allowPhotoEntries: true,
      }),
    ],
  });

  const challengeResults = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("Any dog challenges?", now), "Any dog challenges?", now),
    now
  );
  assert.deepEqual(challengeResults.map((result) => result.id), ["dog-challenge"]);

  const normalResults = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("dog activity", now), "dog activity", now),
    now
  );
  assert.ok(normalResults.some((result) => result.id === "dog-walk"));
});

test("natural language baby query discovers matching baby and toddler activity", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("little-friends", {
        isActive: true,
        title: "Little Friends baby and toddler group",
        category: "Children & Family",
        description: "Friendly sessions for babies and toddlers",
        publicLocation: "Chase Terrace",
        eventDate: fakeTimestamp("2026-09-19T09:30:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "what could I do with my baby in Burntwood",
      location: { text: "Burntwood" },
    }, "what could I do with my baby in Burntwood", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["little-friends"]);
});

test("minor typo variants keep baby group discovery equivalent", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("little-friends", {
        isActive: true,
        title: "Little Friends baby and toddler group",
        category: "Children & Family",
        description: "Friendly sessions for babies and toddlers",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-23T12:45:00Z"),
      }),
    ],
  });

  for (const query of [
    "baby group in burntwood",
    "baby grou in burntwood",
    "baby grup in burntwood",
    "baby groups in burntwood",
  ]) {
    const results = await discoverAskLocalLinkResults(
      db,
      normaliseIntent(heuristicIntent(query, now), query, now),
      now
    );
    assert.deepEqual(results.map((result) => result.id), ["little-friends"], query);
  }
});

test("service and organisation typos match existing candidate vocabulary", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("plumber-1", {
        isActive: true,
        isClaimed: true,
        businessName: "Chase Plumbing",
        category: "Plumber",
        publicLocation: "Burntwood",
      }),
    ],
    organisations: [
      fakeDoc("football-club", {
        isActive: true,
        claimStatus: "approved",
        name: "Burntwood Football Club",
        category: "Fitness & Sport",
        description: "Junior football teams",
        publicLocation: "Burntwood",
      }),
      fakeDoc("camera-org", {
        isActive: true,
        claimStatus: "approved",
        name: "Lichfield Camera Club",
        category: "Hobbies",
        description: "Photography sessions and photo walks",
        publicLocation: "Lichfield",
      }),
    ],
  });

  const plumber = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("plumer", now), "plumer", now),
    now
  );
  const football = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("fotball club", now), "fotball club", now),
    now
  );
  const photography = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("photograpy group", now), "photograpy group", now),
    now
  );

  assert.deepEqual(plumber.map((result) => result.id), ["plumber-1"]);
  assert.deepEqual(football.map((result) => result.id), ["football-club"]);
  assert.deepEqual(photography.map((result) => result.id), ["camera-org"]);
});

test("place typo filters against candidate public location conservatively", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("burntwood-baby", {
        isActive: true,
        title: "Burntwood baby group",
        category: "Children & Family",
        description: "Baby and toddler group",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-23T12:45:00Z"),
      }),
      fakeDoc("lichfield-baby", {
        isActive: true,
        title: "Lichfield baby group",
        category: "Children & Family",
        description: "Baby and toddler group",
        publicLocation: "Lichfield",
        eventDate: fakeTimestamp("2026-09-23T12:45:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("baby group in burntwod", now), "baby group in burntwod", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["burntwood-baby"]);
});

test("messy natural language falls back from empty availability to relevant discovery", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("grass-service", {
        isActive: true,
        isClaimed: true,
        businessName: "Green Grass Cutting",
        category: "Gardener",
        publicLocation: "Burntwood",
      }),
      fakeDoc("dog-groomer", {
        isActive: true,
        isClaimed: true,
        businessName: "Burntwood Pets",
        category: "Dog Groomer",
        publicLocation: "Burntwood",
      }, {
        services: [
          fakeDoc("grooming", {
            isActive: true,
            isPublished: true,
            name: "Dog grooming",
            details: "Bath, tidy and trim",
          }),
        ],
      }),
    ],
    availabilityPosts: [],
    opportunities: [
      fakeDoc("kids-tonight", {
        isActive: true,
        title: "Kids craft night",
        category: "Children & Family",
        description: "Something fun for kids tonight",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-15T18:30:00Z"),
      }),
    ],
  });

  const grass = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("need someone cut grass tomorrow", now), "need someone cut grass tomorrow", now),
    now
  );
  const groomer = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("dog groomer got space friday", now), "dog groomer got space friday", now),
    now
  );
  const kids = await discoverAskLocalLinkResults(
    db,
    normaliseIntent(heuristicIntent("anything for kids tonight", now), "anything for kids tonight", now),
    now
  );

  assert.deepEqual(grass.map((result) => result.id), ["grass-service"]);
  assert.deepEqual(groomer.map((result) => result.id), ["grooming"]);
  assert.deepEqual(kids.map((result) => result.id), ["kids-tonight"]);
});

test("fuzzy matching stays strict for short unrelated terms", async () => {
  const db = fakeDb({
    businesses: [
      fakeDoc("dig-gardens", {
        isActive: true,
        isClaimed: true,
        businessName: "Dig Deep Gardening",
        category: "Gardener",
        publicLocation: "Burntwood",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_service", searchText: "dog" }, "dog", now),
    now
  );

  assert.deepEqual(results, []);
});

test("activity result uses eventTime instead of inventing midnight", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("little-friends", {
        isActive: true,
        title: "Little Friends baby and toddler group",
        category: "Children & Family",
        description: "Friendly sessions for babies and toddlers",
        publicLocation: "Burntwood",
        latitude: 52.681,
        longitude: -1.908,
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "12:45",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      serviceType: "baby",
      location: {
        text: "Burntwood",
        latitude: 52.681,
        longitude: -1.927,
        radiusMiles: 5,
      },
    }, "baby group in Burntwood", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["little-friends"]);
  assert.match(results[0].subtitle, /12:45/);
  assert.doesNotMatch(results[0].subtitle, /00:00/);
  assert.equal(results[0].metadata.dateTime, "2026-09-23T12:45:00");
  assert.ok(results[0].distanceMiles > 0);
  assert.ok(results[0].distanceMiles < 2);
});

test("activity result preserves morning afternoon and evening eventTime labels", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("morning", {
        isActive: true,
        title: "Morning baby group",
        category: "Children & Family",
        description: "Baby group",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "9:05",
      }),
      fakeDoc("afternoon", {
        isActive: true,
        title: "Afternoon baby group",
        category: "Children & Family",
        description: "Baby group",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-23T00:00:00Z"),
        eventTime: "12:45 PM",
      }),
      fakeDoc("evening", {
        isActive: true,
        title: "Evening baby group",
        category: "Children & Family",
        description: "Baby group",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-23T00:00:00Z"),
        eventTime: "7:30 pm",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      serviceType: "baby",
    }, "baby group", now),
    now
  );

  const byId = Object.fromEntries(results.map((result) => [result.id, result]));
  assert.match(byId.morning.subtitle, /09:05/);
  assert.match(byId.afternoon.subtitle, /12:45/);
  assert.match(byId.evening.subtitle, /19:30/);
});

test("activity time filtering uses eventTime for time-of-day constraints", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("midday", {
        isActive: true,
        title: "Midday baby group",
        category: "Children & Family",
        description: "Baby group",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "12:45",
      }),
      fakeDoc("morning", {
        isActive: true,
        title: "Morning baby group",
        category: "Children & Family",
        description: "Baby group",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "09:30",
      }),
      fakeDoc("evening", {
        isActive: true,
        title: "Evening baby group",
        category: "Children & Family",
        description: "Baby group",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "18:30",
      }),
    ],
  });

  const afternoon = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      timeRange: { start: "12:00", end: "17:00" },
    }, "baby group this afternoon", now),
    now
  );
  const morning = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      timeRange: { start: "06:00", end: "12:00" },
    }, "baby group this morning", now),
    now
  );
  const evening = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      timeRange: { start: "17:00", end: "22:00" },
    }, "baby group this evening", now),
    now
  );

  assert.deepEqual(afternoon.map((result) => result.id), ["midday"]);
  assert.equal(morning.some((result) => result.id === "midday"), false);
  assert.ok(morning.some((result) => result.id === "morning"));
  assert.deepEqual(evening.map((result) => result.id), ["evening"]);
});

test("activity time filtering does not invent midnight for date-only activities", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("date-only", {
        isActive: true,
        title: "Date only baby group",
        category: "Children & Family",
        description: "Baby group",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
      }),
      fakeDoc("missing-time", {
        isActive: true,
        title: "Missing time baby group",
        category: "Children & Family",
        description: "Baby group",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "",
      }),
      fakeDoc("malformed-time", {
        isActive: true,
        title: "Malformed time baby group",
        category: "Children & Family",
        description: "Baby group",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
        eventTime: "lunchtime",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      timeRange: { start: "00:00", end: "06:00" },
    }, "baby group early morning", now),
    now
  );

  assert.deepEqual(results, []);
});

test("activity time filtering still supports startTime when eventTime is absent", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("start-time", {
        isActive: true,
        title: "Start time baby group",
        category: "Children & Family",
        description: "Baby group",
        startTime: fakeTimestamp("2026-09-23T08:30:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      timeRange: { start: "06:00", end: "12:00" },
    }, "baby group this morning", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["start-time"]);
});

test("date-only activity result omits fake midnight", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("date-only", {
        isActive: true,
        title: "Date only baby group",
        category: "Children & Family",
        description: "Baby group",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-22T23:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      serviceType: "baby",
    }, "baby group", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["date-only"]);
  assert.match(results[0].subtitle, /23 Sept/);
  assert.doesNotMatch(results[0].subtitle, /00:00/);
  assert.equal(results[0].metadata.dateTime, "");
});

test("activity result still uses non-midnight eventDate when no eventTime exists", async () => {
  const db = fakeDb({
    opportunities: [
      fakeDoc("timestamp-time", {
        isActive: true,
        title: "Timestamp baby group",
        category: "Children & Family",
        description: "Baby group",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-23T08:30:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_activity",
      searchText: "baby",
      serviceType: "baby",
    }, "baby group", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["timestamp-time"]);
  assert.match(results[0].subtitle, /09:30|08:30/);
  assert.notEqual(results[0].metadata.dateTime, "");
});

test("service-routed memory cafe query falls back to public activities", async () => {
  const db = fakeDb({
    businesses: [],
    opportunities: [
      fakeDoc("memory-cafe", {
        isActive: true,
        title: "Burntwood Memory Cafe",
        category: "Social",
        description: "A welcoming memory cafe activity",
        publicLocation: "Burntwood",
        eventDate: fakeTimestamp("2026-09-19T10:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_service",
      searchText: "is there any memory cafe in Burntwood",
      location: { text: "Burntwood" },
    }, "is there any memory cafe in Burntwood?", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["memory-cafe"]);
  assert.equal(results[0].type, "activity");
});

test("strict plumber availability query does not broaden into activities", async () => {
  const db = fakeDb({
    availabilityPosts: [],
    opportunities: [
      fakeDoc("plumber-talk", {
        isActive: true,
        title: "Plumber advice talk",
        category: "Learning",
        eventDate: fakeTimestamp("2026-09-16T10:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_availability",
      searchText: "plumber tomorrow",
      dateRange: { start: "2026-09-16", end: "2026-09-16" },
    }, "plumber tomorrow", now),
    now
  );

  assert.deepEqual(results, []);
});

test("lost dog remains a local community help query", async () => {
  const db = fakeDb({
    communityHelpPosts: [
      fakeDoc("lost-dog", {
        isActive: true,
        status: "active",
        type: "lost_found",
        mode: "lost",
        title: "Lost dog",
        itemCategory: "Pet",
        approxLatitude: 52.681,
        approxLongitude: -1.927,
        discoveryRadiusMiles: 10,
        expiresAt: fakeTimestamp("2026-09-20T12:00:00Z"),
      }),
      fakeDoc("far-lost-dog", {
        isActive: true,
        status: "active",
        type: "lost_found",
        mode: "lost",
        title: "Lost dog",
        itemCategory: "Pet",
        approxLatitude: 53.681,
        approxLongitude: -1.927,
        discoveryRadiusMiles: 10,
        expiresAt: fakeTimestamp("2026-09-20T12:00:00Z"),
      }),
    ],
    opportunities: [
      fakeDoc("dog-walk", {
        isActive: true,
        title: "Dog walking activity",
        category: "Pets",
        eventDate: fakeTimestamp("2026-09-19T10:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_community_help",
      searchText: "lost dog",
      location: {
        latitude: 52.681,
        longitude: -1.927,
      },
    }, "lost dog", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["lost-dog"]);
  assert.equal(results[0].type, "communityHelp");
});

test("community help search without location does not return global missing pets", async () => {
  const db = fakeDb({
    communityHelpPosts: [
      fakeDoc("lost-dog", {
        isActive: true,
        status: "active",
        type: "lost_found",
        mode: "lost",
        title: "Lost dog",
        itemCategory: "Pet",
        approxLatitude: 52.681,
        approxLongitude: -1.927,
        expiresAt: fakeTimestamp("2026-09-20T12:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_community_help", searchText: "lost dog" }, "lost dog", now),
    now
  );

  assert.deepEqual(results, []);
});

test("organisation search ignores generic group wording and matches photography camera data", async () => {
  const db = fakeDb({
    organisations: [
      fakeDoc("camera-org", {
        isActive: true,
        claimStatus: "approved",
        name: "Lichfield Camera Club",
        category: "Hobbies",
        description: "Photography walks and creative sessions",
        publicLocation: "Lichfield",
      }, {
        groups: [
          fakeDoc("walks", {
            isActive: true,
            visibility: "public",
            name: "Photo Walks",
            category: "",
            description: "Friendly photography meetups",
          }),
        ],
      }),
      fakeDoc("running-org", {
        isActive: true,
        claimStatus: "approved",
        name: "Lichfield Running",
        category: "Fitness & Sport",
        description: "Social running sessions",
        publicLocation: "Lichfield",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_organisation",
      searchText: "photography group in Lichfield",
      location: { text: "Lichfield" },
    }, "photography group in Lichfield", now),
    now
  );

  assert.ok(results.some((result) => result.id === "camera-org"));
  assert.ok(results.some((result) => result.id === "walks" && result.parentId === "camera-org"));
  assert.equal(results.some((result) => result.id === "running-org"), false);
});

test("organisation search does not require literal group or club words", async () => {
  const db = fakeDb({
    organisations: [
      fakeDoc("running-org", {
        isActive: true,
        listingOwnershipStatus: "claimed",
        name: "Chasewater Runners",
        category: "Fitness & Sport",
        description: "Weekly running sessions",
        publicLocation: "Brownhills",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_organisation", searchText: "running group" }, "running group", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["running-org"]);
});

test("generic group query can return organisation result cards", async () => {
  const db = fakeDb({
    organisations: [
      fakeDoc("burntwood-group", {
        isActive: true,
        claimStatus: "approved",
        name: "Burntwood Community Group",
        category: "Community",
        description: "A friendly local group",
        publicLocation: "Burntwood",
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_community_help",
      searchText: "a group in Burntwood",
      location: { text: "Burntwood" },
    }, "a group in Burntwood", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["burntwood-group"]);
  assert.equal(results[0].type, "organisation");
});

test("group category can inherit parent organisation category for search", async () => {
  const db = fakeDb({
    organisations: [
      fakeDoc("sports-org", {
        isActive: true,
        claimStatus: "approved",
        name: "Local Active Club",
        category: "Fitness & Sport",
        description: "Local community sport",
      }, {
        groups: [
          fakeDoc("beginners", {
            name: "Beginners",
            visibility: "public",
            category: "",
            description: "New starter sessions",
          }),
        ],
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_organisation", searchText: "fitness beginners" }, "fitness beginners", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["beginners"]);
  assert.equal(results[0].metadata.category, "Fitness & Sport");
});

test("private, malformed and unconfirmed legacy groups remain excluded from public discovery", async () => {
  const db = fakeDb({
    organisations: [
      fakeDoc("camera-org", {
        isActive: true,
        claimStatus: "approved",
        name: "Lichfield Camera Club",
        category: "Photography",
      }, {
        groups: [
          fakeDoc("leaders", {
            isActive: true,
            visibility: "private",
            name: "Leaders",
            description: "Photography leaders",
          }),
          fakeDoc("legacy", {
            name: "Beginners",
            description: "Photography beginners",
          }),
          fakeDoc("malformed", {
            isActive: true,
            visibility: "members_only",
            name: "Malformed",
            description: "Photography malformed",
          }),
        ],
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({ intent: "find_organisation", searchText: "photography" }, "photography", now),
    now
  );

  assert.equal(results.some((result) => result.id === "leaders"), false);
  assert.equal(results.some((result) => result.id === "malformed"), false);
  assert.equal(results.some((result) => result.id === "legacy"), false);
});

test("community help discovery excludes resolved or expired posts", async () => {
  const db = fakeDb({
    communityHelpPosts: [
      fakeDoc("missing-dog", {
        isActive: true,
        status: "active",
        type: "lost_found",
        mode: "lost",
        title: "Missing dog",
        itemCategory: "Pet",
        publicLocation: "Burntwood",
        expiresAt: fakeTimestamp("2026-09-20T12:00:00Z"),
      }),
      fakeDoc("resolved-dog", {
        isActive: true,
        status: "resolved",
        type: "lost_found",
        mode: "lost",
        title: "Missing dog",
        itemCategory: "Pet",
        publicLocation: "Burntwood",
        expiresAt: fakeTimestamp("2026-09-20T12:00:00Z"),
      }),
    ],
  });

  const results = await discoverAskLocalLinkResults(
    db,
    normaliseIntent({
      intent: "find_community_help",
      searchText: "missing dog",
      location: { text: "Burntwood" },
    }, "missing dog in Burntwood", now),
    now
  );

  assert.deepEqual(results.map((result) => result.id), ["missing-dog"]);
});

function fakeTimestamp(iso) {
  const date = new Date(iso);
  return {
    toMillis: () => date.getTime(),
  };
}

function fakeDoc(id, data, children = {}) {
  return { id, data: () => data, _children: children };
}

function fakeDb(collections) {
  return {
    collection: (name) => fakeCollection(collections[name] || []),
  };
}

function fakeCollection(docs) {
  const state = { docs, filters: [], limit: null };
  const query = {
    where: (field, op, value) => {
      state.filters.push({ field, op, value });
      return query;
    },
    orderBy: () => query,
    limit: (value) => {
      state.limit = value;
      return query;
    },
    doc: (id) => ({
      get: async () => {
        const found = docs.find((doc) => doc.id === id);
        return found || fakeDoc(id, null);
      },
    }),
    get: async () => {
      const resultDocs = state.docs
        .filter((doc) => {
          const data = doc.data() || {};
          return state.filters.every((filter) => {
            if (filter.op !== "==") return true;
            return data[filter.field] === filter.value;
          });
        })
        .slice(0, state.limit || undefined)
        .map((doc) => ({
          ...doc,
          ref: {
            collection: (name) => fakeCollection(doc._children?.[name] || []),
          },
        }));
      return {
        docs: resultDocs,
        size: resultDocs.length,
      };
    },
  };
  return query;
}

test("reported unclaimed moderator organisation is discoverable without activities or a claim", async () => {
  const db = fakeDb({ organisations: [fakeDoc("reported-org", {
    name: "Men Walking and Talking", category: "Wellbeing & Support", publicLocation: "Burntwood",
    isActive: true, createdByModerator: true, claimStatus: "unclaimed", listingOwnershipStatus: "unclaimed",
    latitude: 52.6719945, longitude: -1.9428779,
  })] });
  const intent = normaliseIntent({ intent: "find_organisation", searchText: "Men Walking and Talking", location: { latitude: 52.6719945, longitude: -1.9428779, radiusMiles: 15 } }, "Men Walking and Talking", now);
  const results = await discoverAskLocalLinkResults(db, intent, now);
  assert.equal(results.length, 1);
  assert.equal(results[0].type, "organisation");
  assert.equal(results[0].id, "reported-org");
});
