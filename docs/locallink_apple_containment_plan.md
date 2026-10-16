# LocalLink — minimal Apple staff-seat callable containment

Status: PASS local fail-closed tests; BLOCKED production deployment pending explicit approval and fresh source/configuration verification. Nothing is deployed by this plan.

The active local callable and revised candidate reject unverified purchases without entitlement writes. The captured production callable instead accepts recognised product identifiers, sets additional seats and clears Stripe subscription metadata without transaction verification. An absent purchase button does not protect a callable endpoint.

The separate `locallink_apple_containment.patch` changes only the body of `verifyAppleSeatPurchase` in its captured production source cohort: `2f6cb1e4f0b993529bf9e802e755627eb725b9df`. It keeps the callable export name, region `us-central1`, Node 24 runtime and authentication/business-owner checks. The purchase branch throws `failed-precondition` before entitlement creation, writes or seat enforcement. Missing arguments/businesses, outsiders and anonymous callers retain their validation failures. Real product IDs, forged IDs and replays all fail closed; this is containment, not purchase verification.

The baseline/archive/contained-source/patch hashes are recorded in `locallink_apple_containment_identity.json`. Two isolated handler tests pass, and the revised application candidate's real callable emulator test confirms existing entitlements remain byte-for-byte equivalent. Stripe functionality, legitimate subscriptions, staff records and existing appointments remain untouched. Older callers receive a controlled unavailable response; the endpoint is retained.

## Separately approved deployment sequence

1. Request approval specifically for production containment of this callable. Refresh read-only function metadata, source hash, IAM, runtime/configuration and dependencies. If production differs from the captured cohort, prepare and test a new exact minimal diff first.
2. Package the captured compatible source/dependencies plus only this handler correction. Preserve all exports; do not use the broader dirty application source or a blanket Functions deployment. Verify packaging in non-production and confirm the same endpoint/client error contract.
3. After approval, deploy only `verifyAppleSeatPurchase` in the existing region/project. No endpoint deletion, migration, entitlement repair or Stripe record change is included. Deployment may produce ordinary runtime logs, but the handler must perform no business-data writes.
4. Verify deployed source/configuration and non-production forged/real-ID/replay cases. Any live synthetic invocation or production data inspection needs explicit scope; do not test against legitimate customer purchases without authorisation. Monitor errors and entitlement-write absence through approved observability.
5. Recovery must remain fail-closed. Do not restore the unsafe product-ID branch. Prefer a corrected unavailable handler or other reviewed endpoint containment if deployment problems arise.

Signed transaction, product/bundle/environment verification and replay receipts would be prerequisites for any later purchasing enablement. They are outside this security release; no new purchase feature is proposed.
