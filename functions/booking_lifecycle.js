"use strict";

const AUTO_COMPLETE_GRACE_MINUTES = 120;

function autoCompleteCutoffDate(now = new Date()) {
  return new Date(
    now.getTime() - AUTO_COMPLETE_GRACE_MINUTES * 60 * 1000
  );
}

function dateMillis(value) {
  if (value instanceof Date) return value.getTime();
  if (Number.isFinite(value)) return Number(value);
  throw new TypeError("Expected a Date or millisecond timestamp.");
}

function normaliseInterval(interval) {
  const start = dateMillis(interval.start);
  const end = dateMillis(interval.end);
  if (end <= start) {
    throw new RangeError("Interval end must be after start.");
  }
  return { start, end };
}

function intervalMinutes(interval) {
  const normalised = normaliseInterval(interval);
  return (normalised.end - normalised.start) / 60000;
}

function canFitDuration(interval, durationMinutes) {
  return intervalMinutes(interval) + Number.EPSILON >= durationMinutes;
}

function intervalsOverlap(a, b) {
  const first = normaliseInterval(a);
  const second = normaliseInterval(b);
  return first.start < second.end && second.start < first.end;
}

function mergeAvailabilityIntervals(intervals) {
  const sorted = intervals
    .map(normaliseInterval)
    .sort((a, b) => a.start - b.start || a.end - b.end);

  const merged = [];
  for (const interval of sorted) {
    const previous = merged[merged.length - 1];
    if (previous && interval.start <= previous.end) {
      previous.end = Math.max(previous.end, interval.end);
    } else {
      merged.push({ ...interval });
    }
  }
  return merged;
}

function subtractBusyIntervals(freeInterval, busyIntervals) {
  let remaining = [normaliseInterval(freeInterval)];
  const busy = busyIntervals
    .map(normaliseInterval)
    .sort((a, b) => a.start - b.start || a.end - b.end);

  for (const occupied of busy) {
    const next = [];
    for (const free of remaining) {
      if (!intervalsOverlap(free, occupied)) {
        next.push(free);
        continue;
      }
      if (occupied.start > free.start) {
        next.push({ start: free.start, end: Math.min(occupied.start, free.end) });
      }
      if (occupied.end < free.end) {
        next.push({ start: Math.max(occupied.end, free.start), end: free.end });
      }
    }
    remaining = next;
  }

  return remaining.filter(interval => interval.end > interval.start);
}

function subtractBookedInterval({
  availability,
  booking,
  minimumDurationMinutes,
}) {
  const free = normaliseInterval(availability);
  const booked = normaliseInterval(booking);
  if (booked.start < free.start || booked.end > free.end) {
    throw new RangeError("Booking interval must fit inside availability.");
  }

  const fragments = [];
  if (booked.start > free.start) {
    fragments.push({ start: free.start, end: booked.start });
  }
  if (booked.end < free.end) {
    fragments.push({ start: booked.end, end: free.end });
  }

  return fragments.filter(fragment =>
    canFitDuration(fragment, minimumDurationMinutes)
  );
}

function restorableCancelledIntervals({
  booking,
  busyIntervals = [],
  now = Date.now(),
}) {
  const cancelled = normaliseInterval(booking);
  const nowMillis = dateMillis(now);
  if (cancelled.start <= nowMillis) return [];

  return subtractBusyIntervals(cancelled, busyIntervals)
    .filter(interval => interval.end > nowMillis);
}

module.exports = {
  AUTO_COMPLETE_GRACE_MINUTES,
  autoCompleteCutoffDate,
  canFitDuration,
  intervalMinutes,
  intervalsOverlap,
  mergeAvailabilityIntervals,
  restorableCancelledIntervals,
  subtractBookedInterval,
  subtractBusyIntervals,
};
