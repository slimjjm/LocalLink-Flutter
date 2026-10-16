function reusableBookingAddressPreferenceData(customerAddress, updatedAt) {
  const lastAddress = String(customerAddress || "").trim();
  if (!lastAddress) return null;

  return {
    lastAddress,
    updatedAt,
  };
}

module.exports = {
  reusableBookingAddressPreferenceData,
};
