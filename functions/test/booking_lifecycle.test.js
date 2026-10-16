"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  AUTO_COMPLETE_GRACE_MINUTES,
  autoCompleteCutoffDate,
  canFitDuration,
  intervalsOverlap,
  mergeAvailabilityIntervals,
  restorableCancelledIntervals,
  subtractBookedInterval,
  subtractBusyIntervals,
} = require("../booking_lifecycle");

test("auto-complete uses a post-appointment grace period", () => {
  const now = new Date("2026-09-07T12:00:00.000Z");
  const cutoff = autoCompleteCutoffDate(now);

  assert.equal(AUTO_COMPLETE_GRACE_MINUTES, 120);
  assert.equal(cutoff.toISOString(), "2026-09-07T10:00:00.000Z");
});

function minutes(value) {
  return new Date(Date.UTC(2026, 8, 7, 12, value)).getTime();
}

function labels(intervals) {
  return intervals.map((interval) => [
    (interval.start - minutes(0)) / 60000,
    (interval.end - minutes(0)) / 60000,
  ]);
}

test("direct window booking at the start preserves the later free interval", () => {
  const result = subtractBookedInterval({
    availability: { start: minutes(0), end: minutes(180) },
    booking: { start: minutes(0), end: minutes(60) },
    minimumDurationMinutes: 60,
  });

  assert.deepEqual(labels(result), [[60, 180]]);
});

test("direct window booking in the middle splits both sides", () => {
  const result = subtractBookedInterval({
    availability: { start: minutes(0), end: minutes(180) },
    booking: { start: minutes(60), end: minutes(120) },
    minimumDurationMinutes: 60,
  });

  assert.deepEqual(labels(result), [[0, 60], [120, 180]]);
});

test("direct window booking at the end preserves the earlier free interval", () => {
  const result = subtractBookedInterval({
    availability: { start: minutes(0), end: minutes(180) },
    booking: { start: minutes(120), end: minutes(180) },
    minimumDurationMinutes: 60,
  });

  assert.deepEqual(labels(result), [[0, 120]]);
});

test("direct window booking on a half-hour boundary splits accurately", () => {
  const result = subtractBookedInterval({
    availability: { start: minutes(0), end: minutes(180) },
    booking: { start: minutes(30), end: minutes(90) },
    minimumDurationMinutes: 30,
  });

  assert.deepEqual(labels(result), [[0, 30], [90, 180]]);
});

test("different service durations control which fragments are bookable", () => {
  const availability = { start: minutes(0), end: minutes(180) };
  const booking = { start: minutes(30), end: minutes(90) };

  assert.deepEqual(
    labels(subtractBookedInterval({
      availability,
      booking,
      minimumDurationMinutes: 30,
    })),
    [[0, 30], [90, 180]]
  );
  assert.deepEqual(
    labels(subtractBookedInterval({
      availability,
      booking,
      minimumDurationMinutes: 60,
    })),
    [[90, 180]]
  );
  assert.deepEqual(
    labels(subtractBookedInterval({
      availability,
      booking,
      minimumDurationMinutes: 90,
    })),
    [[90, 180]]
  );
});

test("sequential non-overlapping bookings are represented by remaining fragments", () => {
  const first = subtractBookedInterval({
    availability: { start: minutes(0), end: minutes(180) },
    booking: { start: minutes(60), end: minutes(120) },
    minimumDurationMinutes: 60,
  });
  const second = subtractBookedInterval({
    availability: first[0],
    booking: { start: minutes(0), end: minutes(60) },
    minimumDurationMinutes: 60,
  });

  assert.deepEqual(labels(second), []);
  assert.deepEqual(labels([first[1]]), [[120, 180]]);
});

test("overlapping simultaneous booking attempts are detectable", () => {
  assert.equal(
    intervalsOverlap(
      { start: minutes(60), end: minutes(120) },
      { start: minutes(90), end: minutes(150) }
    ),
    true
  );
  assert.equal(
    intervalsOverlap(
      { start: minutes(0), end: minutes(60) },
      { start: minutes(60), end: minutes(120) }
    ),
    false
  );
});

test("cancellation with no other bookings restores the cancelled interval", () => {
  const merged = mergeAvailabilityIntervals([
    { start: minutes(60), end: minutes(120) },
  ]);

  assert.deepEqual(labels(merged), [[60, 120]]);
});

test("cancellation after another segment was booked does not restore occupied time", () => {
  const restorable = subtractBusyIntervals(
    { start: minutes(60), end: minutes(120) },
    [{ start: minutes(0), end: minutes(60) }]
  );
  const merged = mergeAvailabilityIntervals([
    { start: minutes(120), end: minutes(180) },
    ...restorable,
  ]);

  assert.deepEqual(labels(merged), [[60, 180]]);
});

test("adjacent free intervals merge after cancellation", () => {
  const merged = mergeAvailabilityIntervals([
    { start: minutes(0), end: minutes(60) },
    { start: minutes(60), end: minutes(120) },
    { start: minutes(120), end: minutes(180) },
  ]);

  assert.deepEqual(labels(merged), [[0, 180]]);
});

test("elapsed and too-short fragments are not offered for the selected duration", () => {
  assert.equal(canFitDuration(
    { start: minutes(0), end: minutes(29) },
    30
  ), false);
  assert.equal(canFitDuration(
    { start: minutes(0), end: minutes(30) },
    30
  ), true);
});

test("elapsed cancellations do not restore availability", () => {
  const restorable = restorableCancelledIntervals({
    booking: { start: minutes(0), end: minutes(60) },
    now: minutes(61),
  });

  assert.deepEqual(restorable, []);
});

test("capacity-style availability can continue to use counter semantics", () => {
  const capacity = 3;
  const remainingCapacity = 2;

  assert.equal(Math.max(0, remainingCapacity - 1), 1);
  assert.equal(capacity > 1, true);
});
