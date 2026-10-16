"use strict";
const adminId="moderator", businessId="seeded-business";
const now=new Date("2026-09-29T10:00:00.000Z");
function businessPayload(overrides = {}) {
  return {
    createdByModerator: true,
    listingOwnershipStatus: "unclaimed",
    claimedByUserId: null,
    claimedAt: null,
    claimStatus: "unclaimed",
    area: "Burntwood",
    publicLocation: "Burntwood",
    createdAt: now,
    updatedAt: now,
    businessName: "Test Cafe",
    name: "Test Cafe",
    category: "Cafe",
    description: "Independent local cafe.",
    bio: "Independent local cafe.",
    address: "1 High Street, Burntwood",
    latitude: 52.681,
    longitude: -1.831,
    phone: "01543 000000",
    email: "",
    website: "",
    openingHoursStructured: {
      monday: { isOpen: true, periods: [{ open: "09:00", close: "17:00" }] },
    },
    openingHours: "Mon 09:00-17:00",
    serviceRadiusMiles: 5,
    serviceMode: "premises",
    createdBy: adminId,
    ownerId: "",
    businessOwnerId: "",
    isClaimed: false,
    isActive: true,
    acceptingLeads: false,
    paymentMethods: ["cash"],
    stripeRequested: false,
    stripeConnected: false,
    stripeChargesEnabled: false,
    schedulingMode: "simple",
    photoURLs: ["https://example.com/business.jpg"],
    ...overrides,
  };
}

function metadataPayload(overrides = {}) {
  return {
    listingType: "business",
    listingId: businessId,
    sourceUrl: "",
    sourceName: "",
    moderatorNotes: "",
    seededByModeratorUserId: adminId,
    area: "Burntwood",
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

module.exports={businessPayload, metadataPayload};
