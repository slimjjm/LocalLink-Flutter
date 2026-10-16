"use strict";

const COOLDOWN_MS = 24 * 60 * 60 * 1000;

function numberFrom(value) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function distanceMiles(aLat, aLng, bLat, bLng) {
  const values = [aLat, aLng, bLat, bLng].map(numberFrom);
  if (values.some((value) => value === null)) return null;
  const [lat1, lng1, lat2, lng2] = values;
  const radians = (value) => value * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLng = radians(lng2 - lng1);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) *
      Math.sin(dLng / 2) ** 2;
  return 3958.8 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function isActiveMissingPet(report, nowMs = Date.now()) {
  const expiresAt = typeof report.expiresAt?.toMillis === "function"
    ? report.expiresAt.toMillis()
    : numberFrom(report.expiresAt);
  return report.type === "lost_found" &&
    report.mode === "lost" &&
    String(report.itemCategory || "").toLowerCase() === "pet" &&
    report.isActive !== false &&
    !["resolved", "reunited", "closed", "expired", "removed"].includes(
      String(report.status || "").toLowerCase()
    ) &&
    !report.resolvedAt &&
    (expiresAt === null || expiresAt > nowMs);
}

function meaningfulAlertVersion(report) {
  if (report.confirmedSightingVersion != null) {
    return `sighting:${report.confirmedSightingVersion}`;
  }
  if (report.searchLocationVersion != null) {
    return `location:${report.searchLocationVersion}`;
  }
  return "initial";
}

function alertCategory(report) {
  const petType = String(report.petType || "").toLowerCase();
  if (petType.includes("dog")) return "missingDogs";
  if (petType.includes("cat")) return "missingCats";
  return "otherMissingPets";
}

function eligibleMissingPets({
  reports,
  latitude,
  longitude,
  maxRadiusMiles,
  alertedVersions = {},
  excludedReportIds = [],
  enabledCategories = ["missingDogs", "missingCats", "otherMissingPets"],
  recipientId = "",
  nowMs = Date.now(),
}) {
  const excluded = new Set(excludedReportIds);
  const categories = new Set(enabledCategories);
  return reports.flatMap((entry) => {
    const report = entry.data || entry;
    const id = String(entry.id || report.id || "").trim();
    const ownerIds = [
      report.ownerId,
      report.createdBy,
      report.claimedBy,
      report.businessOwnerId,
    ].map((value) => String(value || "").trim()).filter(Boolean);
    if (!id || excluded.has(id) || ownerIds.includes(recipientId) ||
        !categories.has(alertCategory(report)) ||
        !isActiveMissingPet(report, nowMs)) return [];
    const coordinates = require('./public_location').publicCommunityCoordinates(report);
    if (!coordinates) return [];
    const distance = distanceMiles(
      latitude,
      longitude,
      coordinates.latitude,
      coordinates.longitude
    );
    const reportRadius = numberFrom(report.discoveryRadiusMiles) ?? maxRadiusMiles;
    if (distance === null || distance > maxRadiusMiles || distance > reportRadius) {
      return [];
    }
    const version = meaningfulAlertVersion(report);
    if (alertedVersions[id] === version) return [];
    return [{ id, data: report, distanceMiles: distance, version }];
  });
}

function buildNearbyNotification(candidates) {
  if (candidates.length === 1) {
    const candidate = candidates[0];
    const report = candidate.data;
    const petType = String(report.petType || "pet").trim().toLowerCase();
    const name = String(report.title || "A missing pet").trim();
    const location = String(
      report.lastSeenLocation || report.missingLocation ||
      report.location || report.publicLocation || report.area || "nearby"
    ).trim();
    return {
      type: "community_alert",
      title: `Missing ${petType} nearby`,
      body: `${name} was last seen near ${location}.`,
      communityHelpPostId: candidate.id,
    };
  }

  return {
    type: "community_alert_group",
    title: `${candidates.length} missing pets reported nearby`,
    body: "Open LocalLink to see the latest local reports.",
    communityHelpPostId: "",
  };
}

function cooldownAllows(lastSentAtMs, nowMs = Date.now()) {
  const lastSent = numberFrom(lastSentAtMs);
  return lastSent === null || nowMs - lastSent >= COOLDOWN_MS;
}

module.exports = {
  COOLDOWN_MS,
  buildNearbyNotification,
  cooldownAllows,
  eligibleMissingPets,
  isActiveMissingPet,
  meaningfulAlertVersion,
};
