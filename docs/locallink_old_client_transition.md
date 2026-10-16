Current supplement: locallink_client_compatibility_and_acceptance.md and locallink_client_acceptance_matrix.json refresh actual public/custom-domain/device/archive evidence on 10 October. Neither web origin matches tested candidate JS; an installed developer iPhone app is labelled 18.0.5+21 but its source is unverified. No device acceptance pass is claimed. Historical observations below are retained; use the supplement for current evidence and the finite cutover/checklist.

# LocalLink 18.0.5+21 — compatibility-first security transition

Status: PASS local reproducible contracts; BLOCKED installed-cohort validation and production cutover. No unsafe permission exception is proposed.

## Released-client evidence and limits

Read-only Apple lookup on 10 October 2026 reports **V18.0.4**, released 5 October, bundle `Canine-Connections.LocalLink`. The crawled App Store page initially showed stale 18.0.1; the live lookup supersedes it. Public Google Play metadata fetched on 10 October reports **17.0.8** for `com.locallink.app`. These are public storefront observations, not installed-user cohorts or build numbers. Firebase Hosting's previously captured baseline is **18.0.2+18** (1 October release); it was not re-read this pass. Custom-domain/cached web cohorts remain unknown.

Sources: [Apple lookup](https://itunes.apple.com/lookup?id=6757247743&country=gb), [Google Play listing](https://play.google.com/store/apps/details?id=com.locallink.app&hl=en_GB&gl=GB).

The repository has no release tags or verified mapping from these native versions to the tested source. Do not label a particular binary as compatible based only on release notes. App Store Connect/Play Console release/build inventories, original archived binaries/source revisions and installed-device tests are required to identify exact dependencies. This needs read-only account access or user-provided release records; none were available here. Public marketing versions cannot prove a native build number.

## Workflow classification and policy

| Workflow / legacy contract | Classification | Practical handling and local evidence |
|---|---|---|
| Existing bookings, direct availability transactions, cash/bank transfer/Stripe, existing staff and entitlements | Safe to support temporarily | Preserve deployed callable names and data. Eight actual booking-capacity/cancellation/payment emulator regressions pass; full backend suite retains payment/webhook tests. No seat-enforcement retirement. |
| Authorised owner/organiser direct activity reads; public canonical queries; scoped private manager access | Safe to support temporarily | Positive/negative discovery and recurring emulator tests pass, including creator-only legacy and inactive manager records. Scope proves authority; series ID alone does not. |
| Registered users joining public groups, authorised approvals/removal/leaving, existing legitimate membership and own attendance history | Safe to support temporarily | Existing organisation/membership/attendee emulator cases pass. Keep protected roles/invitations; no automatic membership repair, role grants or account reactivation. Verify exact old payloads on archived clients. |
| Broad activity/group discovery; bare recurring-series list used by ordinary organisers | Requires application update | Updated client uses public/owner/organisation/group scopes. Bare shared-series query is denied; revised creator/organiser/org/group queries work. Do not permit broad private reads during an update grace period. |
| Direct legacy review writes | Requires application update | Use the authenticated atomic review callable; retain it through rollback. Legacy direct writes remain rejected. No unvalidated compatibility write exception. |
| Business address-only edits | Requires application update | Require confirmed address and coordinates atomically. Unrelated authorised profile edits remain supported; no automatic re-geocoding. |
| Cross-user attendee history/unauthorised private rosters, private self-join, self-issued privileged memberships, forged roles and unsafe reactivation | Must be disabled/rejected for security | Maintain rule denials immediately at cutover. Ordinary role labels or claims do not grant leadership. Existing legitimate management/participation permissions remain as tested. |
| Apple product-ID-only staff purchase | Must be disabled/rejected for security | Keep endpoint but fail closed; preserve existing entitlements/Stripe state. Minimal production containment deployed and verified on 10 October; Apple blocker CLOSED. |

These classifications describe operation contracts, not verified per-binary certification. Reproducible emulator tests exercise captured current legacy queries/payloads; they do not substitute for installed iOS 18.0.4, Android 17.0.8 or web 18.0.2 binaries.

## Practical cutover

1. Inventory native store builds/source archives, installed cohorts and supported OS versions through approved read-only access. Run the device checklist against those actual binaries and the revised candidate. Record per-workflow support rather than guessing from marketing version.
2. Keep safe booking/payment/messaging/attendance endpoints and all 16 deployed-only application exports plus six Stripe extensions listed in the release manifest. No blanket endpoint cleanup. Do not delete user data, entitlements or appointments.
3. Prepare compatible backend review/capability contracts, indexes and discovery sync; stage first. Approve and rehearse only the safe canonical backfill. Unknown records remain unchanged/manual review. In particular, a linked legacy group activity without established audience can remain directly readable by an authorised member, but member-feed inclusion needs a separately reviewed owner decision; verified manager feeds preserve legacy access. Maintain private exclusions throughout.
4. Make build 21 available through Apple/Google and prepare web replacement before coordinated enforcement. Communicate which discovery/review/address flows require updating using an approved channel. No messages have been sent by this work. Agree a concrete update window/cutover owner only after store approval and cohort evidence; no speculative calendar deadline is imposed.
5. Enforce secure rules at the approved cutover; deny unsafe operations for every version. If old binaries cannot display a friendly update message, document their permission-error behaviour and support instructions. Do not claim the new gate can retrofit an old binary or that an old offline cache can be remotely erased.
6. Enable build-21 public server-managed readiness metadata only after backend, index and privacy coverage validation. Missing/unready metadata, server failure and unsupported capabilities fail closed. This launch/retry gate is UX, not authentication, and cannot remotely gate old clients.
7. Monitor denied operations, old-client support reports, public coverage, booking/payment and messages. Pause release/readiness on failure; recovery must retain secure rules and necessary callables/receipts. Never roll back to vulnerable membership/privacy/Apple handling.

Build-21 readiness metadata remains `ready`, `minimumBuild:21`, `discoverySchema:1`, `reviewApi:1`, `membershipApi:1`, `locationSchema:1`. Creation/update requires separate production-write approval. No future commercial feature or forced-update bridge has been added. If full old-client discovery/review functionality is mandatory, a separately reviewed transitional client is needed; unsafe access is not an option.
