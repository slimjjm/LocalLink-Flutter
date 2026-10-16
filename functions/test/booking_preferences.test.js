const assert = require("node:assert");
const { describe, it } = require("node:test");

const {
  reusableBookingAddressPreferenceData,
} = require("../booking_preferences");

describe("reusableBookingAddressPreferenceData", () => {
  it("stores the successful booking address as the reusable customer address", () => {
    const updatedAt = { sentinel: "serverTimestamp" };

    assert.deepEqual(
      reusableBookingAddressPreferenceData("  77 Edited Lane  ", updatedAt),
      {
        lastAddress: "77 Edited Lane",
        updatedAt,
      }
    );
  });

  it("does not overwrite the reusable address with an empty booking address", () => {
    assert.equal(reusableBookingAddressPreferenceData("   ", {}), null);
  });
});
