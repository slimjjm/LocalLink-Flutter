# LocalLink — Product, Commercial and Usability Audit

Audit completed: 9 October 2026. Project: `/Users/jamesevans/locallink_flutter`.

This is an audit only. Recommendations have not been implemented. No deployment, production database access or production security-rule changes were performed. The separate `/Users/jamesevans/development/locallink_flutter` project was not used.

## 1. Executive Summary

LocalLink has a credible core: local discovery, service enquiries and bookings, Community Help, and recurring community activities. Its main weakness is not missing functionality. Several existing journeys fail at the boundary between the Flutter UI and backend permissions, while onboarding and navigation expose more concepts than a new user needs at once. A service-free business listing offers apparent contact actions without a usable contact destination. Some successful writes are presented as failures because a later, forbidden write fails. These defects can undermine confidence faster than additional features can restore it.

Two private-data permission failures were reproduced using synthetic data in an isolated local Firestore emulator: an anonymous visitor can grant themselves active organisation membership and then read organisation-only activities; a signed-in outsider can read private activity attendee records despite being denied the parent activity. A separate Apple staff-seat entitlement callable trusts a supplied product identifier without verifying a purchase. These require priority attention before expanding private-group use or monetisation. This audit does **not** establish which rules or functions are deployed in production.

Commercially, the strongest proposition is helping a business obtain and manage genuine local enquiries and bookings. The current dashboard offers operational information but insufficient evidence of attributed customer outcomes to establish willingness to pay. Organisations can contribute repeat local participation and useful supply, but volunteer administrators should not be forced through commercial business concepts. Missing-pet reports should remain a simple, trustworthy public-interest service, with private sightings and truthful explanations of alert reach.

**Evidence convention used throughout:**

- **E — locally reproduced:** a behaviour was demonstrated against the checked-in rules in a synthetic emulator experiment. This is not a live production finding.
- **C — confirmed code evidence:** the implementation or inconsistency is directly visible. Runtime impact beyond the stated code path remains unmeasured.
- **U — likely usability concern:** a reasoned interpretation of the visible journey, requiring representative user testing.
- **H — commercial/product hypothesis:** a proposed improvement whose effect must be measured.
- **D — device verification required:** rendering, assistive technology, notification delivery, external links or end-to-end platform behaviour cannot be established from source alone.

Priority means P0: security/entitlement boundary requiring immediate investigation; P1: broken or materially misleading core journey; P2: clarity, accessibility or meaningful friction; P3: experimental improvement. Effort estimates are relative, not delivery commitments.

### Scope and verification

Reviewed navigation/authentication, business onboarding and claims, business profiles/services/availability, bookings and private conversations, dashboard/subscription flows, Community Help creation/discovery/ownership/sightings/lifecycle/alerts, organisation/group permissions and management, activities/attendance/recurrence/reviews, moderation, Firestore rules and relevant backend functions. This was a source-led audit, not a moderated usability study or full mobile penetration test. No real users, transactions or production documents were exercised.

| Check | Result | Interpretation |
|---|---|---|
| `flutter test --no-pub --reporter expanded` | 362 tests passed | Existing Flutter suite passes; it does not establish complete user-journey or permission coverage. |
| `node --test functions/test/*.test.js` | 144 tests passed | Existing backend unit suite passes. |
| `flutter analyze --no-pub` | Six informational findings; no warnings/errors; exit 1 | Deprecated `withOpacity`/`zIndex` and unnecessary underscore findings. No fixes made. |
| Synthetic Firestore experiments | Permission and partial-write findings below reproduced | Local emulator v1.20.4, project `demo-locallink-audit`, current checked-in rules; no production access. |
| Real devices, push delivery, purchase verification, deployed-rule parity | Not tested | Must be verified separately before treating code findings as live behaviour. |

Analyzer locations: `lib/screens/my_opportunities_screen.dart:210`; `lib/screens/recurring_series_manager_screen.dart:339,562`; `lib/widgets/map/map_marker_controller.dart:50`; `lib/widgets/postcode_search_card.dart:48`; `lib/widgets/postcode_search_sheet.dart:94`.

## 2. Business Owner Journey

### Discovery, registration and creating versus claiming

Guest browsing is an appropriate starting point for a local app. `AuthGate` creates anonymous sessions and allows home browsing; `MainTabShell._selectTab` protects Inbox and My LocalLink through the existing `AuthRequiredAction` continuation mechanism. Password accounts have an email-verification gate. The application already has machinery for returning to a requested action after authentication; the recommendation is to use it consistently, not introduce another authentication system.

A newcomer must distinguish a new business from an existing listing they can claim. There are separate verified-code and moderated listing-claim journeys (`claim_business_screen.dart`, `listing_claim_request_screen.dart`, `claim_review_screen.dart`, and backend claim handlers). Those safeguards are valuable. Explain the choice at the point of entry: “Find your business first. If it is already listed, claim it; otherwise add it.” Do not silently grant ownership to somebody who recognises a listing. **U:** test whether a mobile groomer and café owner can choose correctly without assistance.

Registration uses a non-scrolling `Column` in `register_screen.dart`, around lines 85–150. **C/D:** the layout merits small-screen, keyboard and 200% text testing; overflow was not observed on a device during this audit. Also test the continuation through registration **and** email verification, not only direct sign-in. A passed registration method is not evidence that the original customer action resumes correctly after verification.

### Activation and suitability for different businesses

The distinction should be grounded in tasks:

| Concept | Plain explanation | Appropriate example |
|---|---|---|
| Business | Your public business page | Gardener, café, mobile groomer |
| Service | Something a customer can ask about or book | Haircut, garden visit, training session |
| Availability | A time or opening customers can take | Tomorrow's cancelled grooming appointment |
| Activity | A gathering people attend | Community walk or club training |

A hairdresser or personal trainer may benefit from a service catalogue and appointments. A café may initially need a useful listing and contact route. A tradesperson may need enquiries before fixed prices or bookable slots. Treating every business as appointment-ready adds work without necessarily adding value. **H:** context-sensitive guidance is likely to improve activation, but segment demand must be tested.

There is already business setup guidance, a dashboard, service management, photos, staff, availability and payment configuration. Do not build another setup wizard. Improve the existing next-action guidance.

### Confirmed contact dead end

`BusinessDetailScreen` displays “Book a service” and “Ask a question”. Their handlers at approximately lines 469–489 show messages telling the visitor to choose a service below. The service query at lines 563–584 can instead produce “No services yet”. The visible profile does not provide a general phone/email/website action, despite contact information being collected elsewhere. Actual enquiry creation is service-specific (`_ServiceCard._askQuestion`, around line 1055).

**C:** a business with no active services has no usable enquiry route through these primary actions. This is particularly damaging for businesses that complete a profile and assume they are ready to receive customers. **U:** the wording can make both visitor and owner believe more functionality is available than actually exists.

Recommended action: distinguish listing-ready, enquiry-ready and booking-ready states. Hide or explain booking when no bookable service exists. If customer testing validates a need for business-level enquiries, extend the existing private enquiry conversation model with explicit business context; do not require a fake service or introduce a separate chat product. Only a verified owner should receive enquiries for a claimed listing. A moderator is not the business owner.

### Profile edits, location and readiness

**E:** business owners cannot save changed opening hours under the checked-in rules. `BusinessProfileScreen.saveProfile` writes `openingHoursStructured` and `openingHours` when hours are touched; `validBusinessProfileUpdate` in `firestore.rules:1201–1244` omits those fields. A changed-hours update is denied and other edits in that same write also fail. Align the validation with the existing legitimate owner editor, including appropriate value validation.

**C/U:** address editing in the profile changes text without updating coordinates, and onboarding validity can accept typed address text without a resolved location. Discovery uses coordinates. A plausible consequence is a business displayed in the wrong area or omitted from nearby results. Test create, edit and postcode selection end to end; keep address and location updates together, and make unresolved location explicit.

Readiness messages disagree. `BusinessDashboardModel.healthTitle/isHealthy` treats absent Stripe connection, photos/staff/services/availability as health concerns. `BusinessHomeScreen._SetupAlerts` checks a different subset and can say “Your Page is ready for local bookings.” Cash and bank transfer are supported elsewhere. **C:** offline-payment businesses should not be marked unsuitable merely because Stripe is absent; listing completeness and booking prerequisites also differ. Use one coherent readiness assessment tied to the owner's actual chosen workflow.

### Daily work, payments and return value

Existing booking, diary, staff and private messaging functionality is valuable. Customers can make specific enquiries and providers manage availability and confirmed work. Preserve confirmation, cancellation and payment safeguards; fewer taps are not automatically an improvement when money or a booking is involved. Device-test provider and customer cancellation, declined enquiries, changed slots and payment interruption before making reliability claims.

The subscription screen exposes internal terms such as Stripe status, restriction mode and seats. Its `FutureBuilder` also lacks an explicit error view when loading fails. **C/U:** technical billing state is not a convincing value proposition and a permanent loading state is poor recovery. Use plain plan/status language while retaining diagnostic information for support.

**C, conditional runtime impact:** the Stripe portal backend chooses an owned business using a query with `limit(1)` instead of reliably selecting the business supplied by the subscription screen (`functions/index.js`, around 9362; `business_subscription_screen.dart`, around 274). Verify multi-business ownership and billing context; do not assume this affects an owner with one business.

**C, security:** `verifyAppleSeatPurchase` (`functions/index.js:9533–9588`) checks authentication and business ownership but accepts a product ID such as `locallink.staff.3` as sufficient to grant extra slots and change billing metadata. No purchase receipt/signed transaction validation is present in this callable. Do not test this against a live account. Verify genuine transactions, entitlement expiry/refunds and idempotency server-side before granting seats; never erase Stripe metadata on unverified purchase input.

Reasons to abandon: apparently usable contact buttons with no destination; failed hours saves; ambiguous readiness; missing location; authentication that loses intent; unexplained billing states. Reasons to return: timely genuine enquiries, clear upcoming work, simple cancellations, reusable services/availability and credible evidence of business gained. Willingness to pay remains unproven until these outcomes occur reliably.

## 3. Pet Owner Journey

### A. Distressed owner reporting a missing dog

Community Help already supports lost/found reports, photographs, observed date/time, approximate coordinates, private replies, following, sharing, reminders, renewal and resolution. Ask LocalLink can open a prefilled missing-pet draft (`customer_home_screen.dart`, around 292–316). Preserve that shortcut and keep conventional navigation available.

`PostServiceRequestScreen._publish`, around 395–455, requires title, description, area, pet type, observation date and selected coordinates. These mostly serve identification and geographic usefulness. Present the minimum first and explain why the area and last-seen time matter. Additional descriptive details can remain optional. **U/D:** test one-handed use, stress, keyboard dismissal, interrupted photo upload and resuming a draft before reducing required data.

**C:** `_setLostFoundMode`, around 207, clears typed fields and photos when the user switches lost/found mode. Retain shared information or warn before discarding it. This is an especially poor cost for correcting an initial selection under stress.

The form does not silently prefill an arbitrary location. Editing area search clears stale coordinates and publishing requires a selected location. These are useful protections and should be preserved.

### B. Someone who found an unfamiliar cat

Lost versus found is a meaningful, simple choice. However, the found-pet title label says “Pet name, if known” while `_publish` requires a non-empty title. **C:** the wording contradicts validation. Use “Pet name or short description”, with an example such as “Black cat with white paws”. Do not make the finder invent a name.

Date/time selection allows a date without a known time. Preserve that flexibility. Do not conflate the last-seen/found date with the publication date. Found pets currently have a seven-day lifecycle; found objects have fourteen days. If a change is considered, justify it with response and renewal behaviour rather than assuming one interval suits every report.

### C. A nearby person trying to help

The public report, share and private conversation tools are a useful alternative to scattering personal telephone numbers across social posts. Approved ownership matters: community-added reports cannot simply direct sightings to whoever posted them. The unclaimed-report explanation explicitly says private sightings open after the owner claims the report. Preserve that safeguard.

**U:** it creates a genuine helper dead end before an owner claims the report. Investigate whether a carefully moderated sighting intake/forwarding process is needed. Do not replace it with public comments or send private sightings to an unverified claimant merely to reduce friction.

**C:** `_FollowUpdatesButton` around 2624 checks for a UID but not anonymous authentication and directly calls a backend method that requires registered authentication (`functions/index.js`, around 7788). It lacks the existing sign-in continuation and clear failure handling. The activity attendance action has a similar anonymous-user mismatch. Use `AuthRequiredAction` consistently while retaining backend enforcement. Following is receiving updates, not ownership; use “Get updates” where that distinction is unclear.

**C:** `_sendPrivateReply` catches diverse failures and says the post is no longer active. That explanation may be false for a network or permission error. Map genuine expiry separately and offer recoverable failure text without promising delivery.

Nearby-report discovery depends on location. The local empty state says to set a location without an obvious area action in that component. **U/D:** test denied GPS permissions and a person searching for a pet in a different town. Reuse existing postcode/area selection rather than adding another location system.

**C, scale-dependent consequence:** the nearby list takes up to 50 reports before geographic filtering; the backend missing-pet alert candidate query has a 200-report limit, and an alert-subscription query has a 500-record limit without pagination. Relevant local reports or recipients beyond these caps can be missed as data grows. Current production population and actual missed alerts were not measured. Introduce deterministic pagination or appropriate geographic candidate selection before scale makes these silent exclusions routine.

### D. Owner resolving or renewing a report

Owner-only resolution, optional closing updates, expiry reminders and renewal are already present (`_markResolved`, around 603; `_renewPost`, around 637; backend lifecycle processing, around 8079). Lost and found pet reports normally expire after seven days; reminders precede expiry. Keep ownership checks and explain expiry as removing an outdated active report, not deleting the owner's history.

A happy reunion is not the only reason to close a report. Use neutral completion text after “no longer needed”, and reserve celebratory language for “pet found”. Test expired notifications and old external shares so they lead to a clear resolved/expired state rather than imply the pet is still missing.

### Privacy and truthful reach

Coordinates are rounded to three decimal places (`_softCoordinate`, around 554). Current-location labels avoid a leading house number, but searched place descriptions are copied directly into the public label (`_selectLocationSuggestion`, around 243–262). **C:** a selected suggestion containing a full address can contradict the promise of an approximate public area. Rounding coordinates does not remove an address from text. Sanitise public labels independently, preview what will be public, and keep precise private data separate only when genuinely needed.

Backend alerts have geographic preferences, scheduling/cooldown and device-permission constraints. Publication does not prove delivery. “Your community help post is live” confirms publication; it should not be presented as a count of people alerted. Explain that nearby alerts depend on people's preferences and permissions. **D:** real push receipt, deep links, iOS/Android permission denial, duplicate suppression and background behaviour were not verified.

## 4. Organisation Journey

### Creation, claiming and promoting a session

Organisations have their own creation and management, groups, role-aware administration, announcements and activities. Category-dependent group terminology can support teams and classes. A rugby club, children's organiser and charity do not all need the same vocabulary or hierarchy. Preserve an organisation page with optional groups and sessions; allow the simple case to stay simple.

Creation validates basic name/location rather than forcing a complete commercial catalogue. Existing-listing claims use review/ownership paths rather than instant unrestricted ownership. Explain “claim” as taking verified management of an existing page. An organisation is not a business merely because both have an owner.

**E/C:** `CreateOpportunityScreen` first creates the activity, then separately writes organisation summary fields (`activityCount`, `latestAddedSessionAt`, `latestAddedSessionTitle`, around lines 533–546). `validOrganisationOwnerUpdate` does not permit those fields. The local rules experiment confirms the denied summary write. The screen catches the later failure as “Failed”, although primary creation can already have succeeded. Retrying can create a duplicate; that duplicate consequence follows the code path but was not exercised through the UI. Make creation idempotent and maintain aggregates through authorised backend logic; show success for a successfully created primary record.

### Membership and safeguarding: priority defects

**E:** `firestore.rules:1899–1914` allows an authenticated user to create/update their own organisation member document with `role: member` and `status: active`, without requiring an invitation, approved request or legitimate group admission. Anonymous authentication satisfies `signedIn`. `isOrganisationMember` then trusts that active record, and organisation-scoped activities/announcements use this membership. An anonymous outsider self-created membership and read an organisation-only activity in the isolated emulator.

The correction should make membership an authorised outcome of the appropriate join/invitation/approval workflow. Do not broadly remove private scoping or treat every authenticated visitor as a member. Preserve existing manager roles and audit transitions, including attempts to overwrite a prior membership role.

**E:** a recursive attendees rule (`firestore.rules:2361–2363`) allows any signed-in user to read attendee documents. It overlaps the narrower opportunity-attendee rule at lines 2018–2021. An outsider denied a private activity still read its attendee name/photo record. `OpportunityDetailScreen.joinOpportunity` stores identifying attendee fields. This is particularly serious for children's and other safeguarding-related sessions. Restrict reads according to parent visibility and legitimate roster access, including collection-group queries. Firestore overlapping grants are additive: a narrower rule cannot cancel a broader allow. See [Firebase rules structure](https://firebase.google.com/docs/firestore/security/rules-structure).

**E:** an ordinary active private-group member cannot individually read their private group document because the group read rule includes managers/leaders/admins but not ordinary members (`firestore.rules`, around 1850–1856). Correct member access alongside outsider denials, not by making the group public.

**Observed emulator anomaly requiring parity confirmation:** active-only queries returned private activities and private groups in the local experiment, despite some corresponding individual reads being denied. Treat this as a local query/list privacy risk to reproduce with the current staging/emulator setup and deployed rules, not proof of production exposure or a claim that those queries fail. Review list versus get semantics and query constraints explicitly. [Firebase query guidance](https://firebase.google.com/docs/firestore/security/rules-query) explains why rules and query shape must be evaluated together.

### Attendance, reviews and engagement

**E/C:** `joinOpportunity` commits attendance/count changes, then attempts a client write into the organiser's notifications. `firestore.rules:1675` forbids client notification creation. The local experiment confirms the primary write can succeed before notification is denied; the screen then reports “Unable to join activity”. An organiser and member can end up with different interpretations of the same attendance record. Use existing backend notification infrastructure, with idempotency, and derive visible state from the committed attendance record.

**E/C:** `ReviewService.addReview` writes the review, then performs the same forbidden notification write before updating aggregates. The local experiment confirms the review succeeds and notification fails, preventing the later aggregate step. Additionally, first-review eligibility is not reliably established by the detail UI and the review-create rule only establishes registered reviewer ownership, not attendance. Validate eligibility and ratings server-side and update aggregates reliably. Do not call all existing reviews “verified” without that validation.

An ordinary member's ongoing relationship is less visible than the manager's. `MyLocalLinkOrganisationService.loadManaged` selects management roles rather than ordinary membership; joined individual activities and managed organisations are not a complete “my groups” return journey. **U:** validate whether members can easily return to their club and next session, then surface existing memberships in My LocalLink if this gap is confirmed. Do not duplicate administration screens for ordinary members.

### Recurrence and alternatives to Facebook/WhatsApp

Recurring series management, cancellation/skip, resume and end dates already exist. The backend has transaction-based occurrence protection. Do not rebuild recurrence. **C/D:** monthly date arithmetic uses `Date.setMonth` and needs a defined end-of-month policy; test 31 January, short months, daylight-saving changes, timezone interpretation, edits and duplicate scheduler execution. These are targeted reliability tests, not a proposal for another scheduling engine.

LocalLink's reason to coexist with Facebook/WhatsApp is public local discovery plus a structured, reusable next-session journey with appropriate private member information. It will not win merely by reproducing a general chat feed. For a charity, a clear next activity and volunteer response can be more valuable than multiple engagement mechanics. **H:** test whether reliable recurrence and easy member return increase weekly use before expanding challenges, announcements or paid club features.

## 5. Language and Terminology

These are targeted proposals, not a wholesale renaming exercise. UI behaviour must be corrected where wording currently makes an untrue promise.

| Current wording/concept | Proposed wording | Reason | Screen/code location | Priority/evidence |
|---|---|---|---|---|
| “Book a service” with no services | “Bookings aren't available yet” or omit action | Avoid an unusable primary action; depends on profile state | `business_detail_screen.dart`, `_PrimaryBusinessActions` | P1 C/U |
| “Ask a question” → “Choose a service below…” | “Ask about this service”; business-level “Contact business” only when supported | Match destination and make a service-free contact route honest | Same screen; `_ServiceCard._askQuestion` | P1 C/U |
| “Your Page is ready for local bookings.” | State-specific “Your listing is live” / “You're ready to take bookings” | Listing publication and bookability differ | `business_home_screen.dart`, `_SetupAlerts` | P1 C |
| “Needs Attention” / “Almost Ready” | “Next: add a service” or another relevant task | Give one actionable next step; don't mandate Stripe for offline payment | `business_dashboard_model.dart`, `healthTitle` | P2 C/U |
| “Pet name, if known” | “Pet name or short description” | Align with required title and an unknown found animal | `post_service_request_screen.dart`, found-pet fields | P2 C |
| “Keep a lookout” as follow action | “Get updates” with short explanation | Following updates is not ownership or reporting a sighting | `_FollowUpdatesButton` | P2 U |
| All reply failures: “This post is no longer active.” | Actual expired state, otherwise “Your message wasn't sent. Please try again.” | Avoid a false explanation; retain draft | `_sendPrivateReply` | P1 C |
| “Great news” after any resolution | “Report closed” except reunion-specific flow | Some closure reasons are not happy news | `_markResolved` | P2 U |
| “Set your location…” with no local action | “Choose an area” with area-picker action | Turn instruction into a usable recovery | Nearby Community Help empty state | P2 U/D |
| “Failed: …” after activity creation | Outcome-specific confirmation/error | A successfully created activity should not invite duplicate creation | `create_opportunity_screen.dart`, save/catch | P1 E/C |
| “Unable to join activity” after attendance commits | “You're going” from committed state; separate notification issue | Align feedback with saved participation | `opportunity_detail_screen.dart`, `joinOpportunity` | P1 E/C |
| “I'm going” | Keep for public sessions; explain attendance if needed | Natural language already communicates participation | Activity detail action | Keep/U |
| “Join” | Keep for group membership; qualify “Request to join” where approval is required | Membership and attendance have different consequences | Organisation group membership card | P2 U |
| “Claim” | “Is this your business/organisation? Claim this page” | Explain the established term rather than rename the process | Claim entry and claim screens | P2 U |
| “Availability” | “Available appointments” where appointment-specific | Make the benefit concrete; retain broader wording for non-appointment cases | Business setup/availability entry | P2 U |
| “Stripe Status”, “Restriction Mode”, “Included/Extra Seats” | “Payment connection”, “Account needs attention”, “Included/extra team members” | Move provider/internal terms out of ordinary owner tasks | `business_subscription_screen.dart` | P2 C/U |
| “Skip occurrence?” / “Cancel occurrence?” | “Skip this session?” / “Cancel this session?” | Describe the single-instance effect in ordinary language | `recurring_series_manager_screen.dart:72,97` | P2 U |
| Drawer description “Offer a service or host activity” without business creation choice | Match actual choices; add contextual existing business entry if appropriate | Avoid suggesting an action the chooser does not provide | Home create entry/chooser | P2 C/U |
| “My LocalLink” | Keep; explain empty states with actions | Broad enough for owner, member and helper | Main navigation | Keep/U |
| “Save” versus “Follow” | Keep separate where one is bookmarking and the other sends updates | Do not collapse different consequences | Relevant saved/update controls | Keep/U |
| “Leads” | “Enquiries” for customer messages | Familiar British English and a concrete outcome | Any owner-facing enquiry summary | P2 U; verify each rendered label before replacing |

“Opportunities” can remain an internal model name. Prefer “Activities” or the existing category-specific label in public UI where users are attending something. Do not churn filenames/models merely to improve visible terminology. “Community Help”, “business”, “organisation” and “group” are useful distinctions when explained at the right time.

## 6. Simplification Opportunities

### Action counts: source-derived, not measured device timings

A user action here means tapping a control, entering a field, selecting a result, or confirming a picker. Text entry counts as one action per field, regardless of characters. Counts exclude scrolling, loading, OS permission prompts, email verification and photo-picker operations unless stated. They are route estimates under stated conditions; guest and interrupted journeys cost more. Exact controls can vary by role and category.

| Task and starting point | Current source-derived route | Realistic improvement | Necessary friction to retain |
|---|---|---|---|
| Ask about a listed service, starting on business detail, signed in | Choose service/question action → compose message → send: approximately 3 actions | Keep about 3; label destination clearly | Private conversation, block and ownership checks |
| Ask a business with no services, starting on detail | Ask button → instruction → empty services list: no successful completion | If validated, contact action → compose → send: about 3 | Verified recipient and abuse controls |
| Lost-pet draft already opened, no photo | Enter title, description, pet type; type area and select result; choose observed date and optionally time; publish: approximately 8–10 actions | Keep required identification/area/date, retain data on mode change; use prefilled draft and optional time: approximately 7–9 | Correct location, ownership, publication confirmation |
| Follow an existing report, signed in | One follow action | Keep one | Updates consent and ownership distinction |
| Follow as guest | One tap currently reaches registered-only backend without a complete sign-in recovery | Follow → sign-in/registration → resume follow; variable account steps | Registration and notification permissions where relevant |
| Attend an activity, signed in | One attendance action; subsequent backend write can cause misleading failure | Keep one with authoritative committed-state feedback | Any applicable capacity/private-access checks |
| Close an owned report, already on detail | Resolve action → choose reason → confirm/optional closing update: approximately 3–4 | Keep roughly 3–4; neutral completion copy | Owner permission and accidental-closure protection |
| Create an organisation from its form | Name and location input, category if changed, save; optional details add actions | Keep minimum, make next activity prominent after success | Existing-listing check/verified claims |
| Publish organisation activity from form | Complete required activity fields/location/date-time → publish → secondary summary write | Same user inputs; remove retry-inducing partial-failure path | Scope, organiser ownership and date checks |

These counts identify dead ends and unnecessary repeated work more reliably than a global promise to “halve taps”. Before design changes, observe six business owners, four pet-related users and five organisation administrators/members on devices with realistic data and denied permissions.

### Keep, combine, reposition, simplify

- **Keep:** conventional search alongside Ask LocalLink. Conversational discovery is useful but should not be the only route when an urgent helper already knows their task.
- **Simplify:** reuse existing authentication continuation, location search and owner dashboard guidance; do not add parallel implementations.
- **Combine presentation, not data:** a single next-action area can explain listing/services/availability/payments without merging those distinct domain records.
- **Reposition:** put the owner's highest-value next action above peripheral management options; make “next session” easy for returning members.
- **Better explain:** claim versus create, public visibility versus restricted joining, approximate public area, and alert delivery limitations.
- **Consider hiding from first-use choices:** community challenges, advanced recurrence controls and secondary promotional options unless relevant to the selected task. Existing users should retain access.
- **Do not remove yet:** groups, recurrence, staff management, claims, payment choices or Ask LocalLink. Their users and consequences differ; removal needs usage and interview evidence.

### Accessibility evidence

The business onboarding hero uses white text on an orange gradient (`business_onboarding_screen.dart`, around 513–540). Calculated sRGB contrast is approximately **3.05:1** for white on `#F26A2E` and **2.59:1** on `#FF7A3D`. **C:** the normal-sized supporting text does not meet the 4.5:1 minimum; the lighter endpoint also falls below 3:1 for large text. This is a colour-pair calculation, not a whole-screen compliance assessment. See [W3C contrast guidance](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html). Darken the text background or use suitable dark text while preserving the visual identity.

**C/D:** fixed-height business action cards, the small bottom-navigation labels and the registration `Column` need testing at large text sizes. LocalLink's shared button includes semantics and a minimum height, which is useful, but ellipsis/max-line behaviour still needs inspection. A gesture-only onboarding back control needs a meaningful button label and accessible activation. Separately rendered form question labels may not be associated with their text fields for a screen reader. Verify VoiceOver/TalkBack reading order, focus after dialogs/errors, keyboard navigation where supported, and at least 200% text scaling. [W3C resize-text guidance](https://w3c.github.io/wcag/understanding/resize-text.html) supports this test, but runtime compliance was not established.

## 7. Commercial Assessment

### Value now versus evidence still missing

The application offers local visibility, specific enquiries, appointments, availability, team operations and community activity discovery. Those can save time or produce work. A subscription requires demonstrated recurring outcomes, not a longer feature list. Café/trades enquiries and appointment-business bookings should be measured separately. Do not force an unpaid listing or cash-based business through Stripe to establish usefulness.

`BusinessDashboardService` supplies operational booking, revenue and message information. `business_view` analytics in `BusinessDetailScreen`, around 146, records category/source but does not provide a business identifier suitable for a straightforward per-business views-to-enquiries dashboard. **C:** current instrumentation is insufficient to infer an owner's attributed funnel from that event alone. Revenue estimates are not proof of completed/paid work or incremental business gained.

### Five most commercially valuable improvements

| Rank | Improvement | Revenue/retention mechanism | Minimum measurement | Confidence |
|---|---|---|---|---|
| 1 | Make service-free listings useful and contact actions honest | More listed businesses become reachable; fewer visitors leave before an enquiry | Listing → first enquiry; no-service profile exits; owner reply rate; segment by business type | Contact gap C; commercial lift H |
| 2 | One relevant activation next step using existing dashboard | Owners complete what their actual business needs, without irrelevant staff/Stripe pressure | Time to first usable listing/service; time to first enquiry/booking; setup abandonment | Conflicting readiness C; lift H |
| 3 | Reliable enquiry/attendance/review/notification outcomes | Trust and accurate status encourage repeat use and reduce support effort | Primary-write success vs displayed failure; repeat bookings; response time; complaints | Partial writes E/C; retention lift H |
| 4 | A small, credible owner outcome summary | Owners can judge whether LocalLink earns its cost | Attributed profile views, genuine enquiries, confirmed/completed bookings, repeat customers; explain definitions | Instrumentation gap C; willingness to pay H |
| 5 | Reliable next-session and member-return journeys for local organisations | Repeated community use improves useful local supply and reasons for residents to return; may support business demand | Repeat sessions, attendance continuity, member return, local business enquiries in active areas | Existing recurrence C; ecosystem effect H |

Use existing booking/conversation data and modest aggregation rather than constructing a large analytics platform. Avoid fabricated reach, delivery and conversion counts. Explain whether revenue is estimated, booked, completed or paid.

Run a small geographic pilot with useful local supply and four-week owner cohorts. Interview the example business types about actual enquiries and time saved, not whether they like features. Track repeat use and owner willingness to continue at a stated price. No price or conversion target is justified by this code audit alone. A charity's continued participation and a business's willingness to pay are different outcomes.

Cosmetic wording and layout polish support comprehension but have indirect revenue mechanisms. Reliability, reachable listings and demonstrable customer outcomes come first. Do not monetise urgent missing-pet sightings, private-data protection or basic report closure. Paid staff capacity can be a defensible model only after purchase entitlement and billing-context correctness are established.

## 8. Prioritised Recommendations

Evidence references identify checked-in source, not a deployed production version. Estimates include focused regression tests; security corrections may require wider schema/query compatibility work.

| ID / priority | User type | Finding | Evidence and file references | User impact | Commercial impact | Recommended action | Effort | Regression risk |
|---|---|---|---|---|---|---|---|---|
| R01 P0 | Private organisation members, guests | Self-issued active membership bypasses intended admission | E: `firestore.rules:1899–1914`, `isOrganisationMember:276–281`, scoped activity read:320–359 | Private activity exposure; announcements share same membership dependency by C | Trust/safeguarding liability | Authorised server-managed admission; preserve roles; test anonymous/outsider/invited/member matrices | Medium | High: join/approval/claims compatibility |
| R02 P0 | Private activity attendees | Recursive attendee read overrides parent-scoped rule | E: `firestore.rules:2018–2021,2361–2363`; `joinOpportunity` identifying attendee fields | Name/photo roster exposure despite private parent denial | Serious trust loss | Scope roster access and collection-group reads; reproduce query anomaly against staging parity | Medium | High: attendee views/queries |
| R03 P0 | Paying business owners | Apple staff entitlement accepts unverified product ID | C: `functions/index.js:9533–9588`, `verifyAppleSeatPurchase` | Entitlement/billing integrity failure; live exposure unverified | Subscription integrity risk | Verify signed transaction/receipt and ownership/expiry/refunds before mutation; preserve Stripe metadata | Medium | High: billing migration/platform paths |
| R04 P1 | Businesses/customers | Service-free listing primary contact is a dead end | C: `business_detail_screen.dart:469–489,563–584,1055` | No successful enquiry from primary action | Lost activation and potential customers | Honest state-dependent actions; validate business-level enquiry need using existing messaging | Medium | Medium: recipient/routing safety |
| R05 P1 | Business owners | Edited opening hours denied | E/C: `business_profile_screen.dart`, `saveProfile`; rules:1201–1244 | Legitimate profile save fails | Abandonment/support cost | Validate and permit intended owner fields | Small | Medium: profile validation |
| R06 P1 | Business owners/customers | Address text and geographic coordinates can diverge | C/U: business profile save; onboarding validity/location selection | Wrong/missing nearby discovery | Lost local matching | Resolve and save location coherently; test typed and selected addresses | Medium | Medium: existing locations |
| R07 P1 | Organisers | Activity created before forbidden summary write; UI says failed | E/C: `create_opportunity_screen.dart:533–558`; organisation owner rule:681 onwards | Confusion and possible duplicate retries | Weak repeat publishing | Idempotent primary creation; authorised aggregate maintenance; truthful success | Medium | Medium: summary consumers |
| R08 P1 | Activity participants | Attendance saved before forbidden notification; UI says failed | E/C: `opportunity_detail_screen.dart:569–665`; rules:1675 | Uncertain attendance | Repeat participation/support loss | Existing backend notification path; committed-state UI; deduplicate | Medium | Medium: counts/notifications |
| R09 P1 | Reviewers/organisers | Review partial writes and weak eligibility enforcement | E/C: `review_service.dart:36–136`; rules:1723–1726; detail add-review branch | Saved review inconsistent with feedback/aggregate; questionable eligibility | Trust in ratings | Validate eligibility/rating server-side and aggregate idempotently | Medium | High: legacy reviews/aggregates |
| R10 P1 | Ordinary private-group members | Legitimate member cannot individually read private group | E: group read rule around1850–1856 | Cannot reliably return to own group | Organisation retention | Member-scoped access with outsider denial and list/get tests | Medium | High: privacy/query parity |
| R11 P1 | Guest helpers/participants | UID-only guards reach registered-only actions | C: `_FollowUpdatesButton`; `joinOpportunity`; backend registered guard | Action fails instead of sign-in continuation | Reduced participation | Reuse `AuthRequiredAction`, resume intent, retain server controls | Small | Medium: verification/continuations |
| R12 P1 | Pet owners | Public search label can include address despite approximate-area promise | C: `_selectLocationSuggestion:243–262`; `_softCoordinate:554` | Potential textual location disclosure | Trust/safety | Sanitise public area text independently; preview public output | Medium | Medium: geocoding/share displays |
| R13 P1 | Owners/helpers at scale | Candidate/recipient limits can silently exclude local reports/alerts | C: nearby report limit50; backend candidates200/subscriptions500 | Uneven visibility/alerts; extent unmeasured | Reliability/retention | Deterministic pagination/geographic query strategy; boundary tests | Medium | Medium: costs/dedup/order |
| R14 P2 | New business owners | Readiness checks disagree and over-assume Stripe | C: `business_dashboard_model.dart`; `business_home_screen.dart`, `_SetupAlerts` | Unclear next step | Lower activation hypothesis | One workflow-aware readiness model; preserve cash/bank transfer | Medium | Medium: modes/legacy listings |
| R15 P2 | Distressed pet reporters | Mode change discards content/photos | C: `_setLostFoundMode`, `post_service_request_screen.dart` | Repeated work or abandoned report | Public-service trust | Retain shared draft fields or confirm destructive change | Small | Low: field compatibility |
| R16 P2 | Found-pet reporter | Optional-name label but required title | C: found-pet form and `_publish` | Confusing validation | Reduced reporting | Name-or-description label/example | Small | Low |
| R17 P2 | All users | False generic failure explanations and technical labels | C/U: reply catch, subscription status, recurrence dialogs; section5 | Poor recovery/comprehension | Support cost | Specific recoverable errors and targeted plain-language copy | Small | Low: translations/state wording |
| R18 P2 | Low-vision/screen-reader users | Orange/white contrast; scaling and labels need device verification | C contrast; D scaling: onboarding/register/shared buttons/main dock | Potential exclusion | Reduced audience/completion | Fix proven contrast; test VoiceOver/TalkBack, keyboard and200% text | Medium | Medium: layout |
| R19 P2 | Organisation members | Returning member journey less visible than manager journey | U: `MyLocalLinkOrganisationService.loadManaged`; group membership UI | Hard to find next group/session | Repeat engagement hypothesis | Observe members; surface existing memberships if confirmed | Medium | Medium: role privacy/navigation |
| R20 P2 | Recurring organisers | Monthly/DST semantics need targeted verification | C/D: `functions/recurring.js`, `addRepeatInterval`; recurring manager | Potential date surprise | Repeated-session reliability | Define end-of-month/timezone policy; regression scenarios | Medium | Medium: series compatibility |
| R21 P1 conditional | Multi-business owners | Portal may select first owned business, not selected business | C: `functions/index.js`, portal around9362; subscription screen274 | Wrong billing context if multiple owned businesses | Billing trust/support | Enforce selected business ownership/context | Small | Medium: existing billing |
| R22 P2 | Paying owners | Subscription loading has no explicit error recovery | C: subscription `FutureBuilder` | Indefinite spinner on failure | Conversion/support loss | Retryable error state with retained context | Small | Low |
| R23 P3 | Business owners | Outcome evidence insufficient for subscription case | C instrumentation; H value: `business_view`; dashboard service | Cannot judge value clearly | Willingness-to-pay hypothesis | Lean defined outcomes summary and pilot measurement | Medium | Medium: attribution/privacy |
| R24 P3 | Organisations/helpers | Unclaimed sightings and local-area fallback need validation | U/D: unclaimed report explanation; nearby GPS empty state | Helpful intent can reach a dead end | Community usefulness | Observe denied-GPS/unclaimed cases; reuse area picker; investigate moderated intake only if needed | Medium | High for intake; low for picker |

### Security validation notes

Synthetic experiments created only demo users/documents, exercised current local rules, and cleared only the demo emulator data. They demonstrated R01, R02, R05, R07's summary denial, R08's partial-write sequence, R09's partial-write sequence and R10. They did not execute the purchase callable, real payments, push delivery or production membership changes.

Existing passing tests include source-structure assertions and cannot substitute for adversarial permission tests. Add negative tests for anonymous/outsider reads and writes, approved membership, private rosters, collection-group list/get behaviour, legitimate owner edits, partial write recovery and aggregate authority. Do not “fix” client notification failures by permitting arbitrary client writes to another user's notifications.

## 9. Top 10 Changes

1. **Close private membership and attendee boundaries** (R01/R02), restoring legitimate private-member access at the same time (R10). Confirm deployed parity before declaring a live incident; investigate promptly.
2. **Verify staff-seat purchases before granting entitlements** (R03), and confirm selected-business billing context (R21).
3. **Make service-free business profiles honest and useful** (R04): valid contact destination or clear unavailable state; test a lean enquiry extension before adding it.
4. **Make organisation activity publishing atomic in user meaning and safe to retry** (R07).
5. **Show authoritative attendance success and send notifications through the existing backend** (R08).
6. **Repair review submission, eligibility and aggregates** (R09).
7. **Allow legitimate opening-hours edits with appropriate validation** (R05).
8. **Keep geographic meaning and public privacy consistent**: business address/coordinates and pet public area labels (R06/R12); harden capped discovery as scale warrants (R13).
9. **Give guest helpers a reliable sign-in-and-resume path** (R11), retaining backend permissions.
10. **Offer one relevant business next step and visible evidence of useful outcomes** (R14/R23), with pilot measurement rather than assumed subscription demand.

Contrast and destructive pet-mode switching are small, worthwhile parallel fixes; their omission from this ten does not mean they should wait behind a long analytics project.

## 10. What NOT to Change

- Preserve the friendly hyperlocal identity, existing visual system and architecture. Fix targeted contrast rather than redesigning the app.
- Preserve guest browsing and conventional discovery alongside Ask LocalLink. Restrict sensitive actions appropriately and explain authentication.
- Preserve verified/moderated claims and the distinction between genuine owner, poster, follower and moderator.
- Preserve private conversations, block/participant checks and server-controlled notifications. Do not publish personal contact data to bypass friction.
- Preserve lost/found mode, observed dates, mandatory resolved geographic selection, approximate-location intent, owner-only resolution, reminders and renewal. Correct implementation/copy gaps.
- Preserve cash/bank transfer alongside supported online payment. Avoid mandatory Stripe activation for a use case that does not need it.
- Preserve service-specific booking and enquiry context, confirmation/cancellation protections and staff/diary tools. These serve real appointment businesses.
- Preserve organisation/group/activity distinctions where they represent actual permissions and repeat sessions. Use progressive explanation, not one undifferentiated feed.
- Preserve the existing recurrence engine and instance controls; test calendar edge cases rather than rebuilding scheduling.
- Preserve optional category-dependent organisation vocabulary. Do not force clubs and charities to speak like paying commercial providers.

These are features with sound purposes and implementation evidence, not a claim that every platform edge case already works. End-to-end testing remains necessary where stated.

## 11. Product Bloat Assessment

LocalLink spans commerce, community help and organised participation. That breadth can reinforce hyperlocal usefulness, but exposing every concept to every newcomer makes the app feel larger than the task. The main bloat is **decision and terminology load**, not proof that entire domains should be deleted.

Business setup currently mixes listing completeness, services, availability, staff and payment readiness. Organisers can encounter organisations, groups, activities, events, recurring series and challenges. A distressed pet owner needs none of those decisions. The right response is task-specific entry and progressive disclosure inside the current navigation, with reliable return paths.

| Candidate | Recommendation | Evidence required before removal |
|---|---|---|
| Multiple create entry points | Keep contextual shortcuts; make chooser wording/routes consistent | Observe discovery success and wrong-route rates |
| Service and availability | Keep separate; explain and group setup presentation | Determine whether each business type needs slots or enquiries |
| Organisation/group/activity hierarchy | Keep; make groups optional and role-sensitive | Interview ordinary members and multi-team clubs |
| Ask LocalLink plus manual search | Keep complementary fallback | Compare successful task completion, not novelty usage |
| Community challenges/secondary engagement | Stop expansion until value is shown; reduce first-use prominence if appropriate | Existing active cohorts, completion, organiser demand and return effect |
| Staff-seat/billing controls | Keep for team businesses; disclose when relevant | Single-owner versus team uptake and support burden |
| Claims/moderation | Keep; explain | Abuse, duplicate ownership and verification effectiveness |
| Owner dashboards and readiness alerts | Consolidate guidance, not underlying operations | Which next actions lead to first real customer outcomes |

No feature is recommended for outright removal based only on this audit. If usage proves a feature unused, first identify dependent users, exported/shared links and any permission/lifecycle consequences. Sunset gently rather than deleting a useful minority workflow to make a menu shorter.

Avoid adding a social network, separate messaging infrastructure, broad CRM, club payment suite or large analytics warehouse. First demonstrate a repeated task the existing system cannot support. A contact route for service-free businesses is a specific candidate because an actual dead end exists; an entire new product domain is not justified.

## 12. Suggested Implementation Roadmap

### Quick wins: scoped repairs and truthful language

Implement only after separate authorisation. These are not changes made by this audit.

- Investigate deployed parity for R01–R03 immediately. Begin narrow security tests and containment planning; do not wait for a redesign or usage research. **E/C; Medium; high compatibility risk.**
- Repair owner opening-hours validation (R05), guest action continuation (R11), found-pet label (R16), destructive draft switching (R15), subscription load recovery (R22) and specific recoverable errors (R17). **E/C, with U copy; Small; low-to-medium risk.**
- Correct proven onboarding contrast and label obvious gesture-only controls (R18). Verify the result on devices and at enlarged text. **C/D; Small-to-Medium; layout risk.**
- Make service-free booking/contact states truthful while validating the contact model (R04). Do not leave enabled dead-end actions waiting for research. **C/U; Small for state/copy, Medium for enquiry extension.**
- Confirm portal context for multi-business owners (R21). **C, conditional impact; Small; billing regression checks required.**

### Medium-sized improvements: reliable end-to-end journeys

- Fix organisation publication, attendance and review partial-write handling using authorised backend paths and idempotency (R07–R09). Test retries, offline interruption and already-saved records. **E/C; Medium; existing data/notification compatibility.**
- Complete private-member read/list tests and role transitions after security fixes (R01/R02/R10). Include anonymous, banned/blocked where relevant, outsider, pending applicant, active member, leader, secretary, owner and administrator. **E/C; Medium; high privacy risk.**
- Keep business location and public pet area text coherent (R06/R12); test searched street addresses, manual edits and denied GPS. Harden discovery/alert caps with boundary fixtures (R13). **C/U/D; Medium.**
- Unify readiness around listing/enquiry/booking use cases (R14). Observe a café, tradesperson, gardener, hairdresser, mobile groomer and personal trainer completing setup. **C inconsistency; H improvement; Medium.**
- Test recurrence end-of-month and daylight-saving policy (R20), member return (R19), expired shares/alerts and authentication after email verification. **C/U/D; Medium.**

### Strategic changes requiring discussion and evidence

- Pilot business-level enquiries using the existing conversation system only if owner/customer observation confirms the service-free contact need cannot be met by clearer existing setup. Measure time to first genuine enquiry and recipient response. **H grounded in C dead end; Medium.**
- Build a modest, defined owner outcomes summary (R23), then test willingness to pay against actual value over repeated weeks. Avoid unverified reach/revenue totals and arbitrary price assumptions. **H; Medium.**
- Validate whether member-return improvements and recurring local sessions produce durable community participation before expanding paid organisation tools. **H; Medium.**
- Investigate moderated sighting intake for unclaimed reports only with an explicit safeguarding/ownership model and demonstrated unmet need (R24). Never route sensitive messages to an unverified claimant. **U/H; potentially Large and high safety risk.**
- Evaluate low-use peripheral features for reduced prominence or eventual retirement only after dependency and usage review. **H; effort/risk depends on feature.**

### Acceptance and research gates

A corrected rule must deny the outsider **and** permit the legitimate user. A corrected write journey must show the saved truth after timeout/retry and avoid duplicate records or notifications. A simplified form must retain required privacy, ownership and payment confirmations. A commercially successful improvement must change measured enquiries, useful bookings, response or repeat participation—not just increase button taps.

Device test matrix: iOS and Android; small phone and large text; VoiceOver/TalkBack; guest/registered/unverified/verified accounts; denied location/push/photos; interrupted network; empty and populated business profiles; cash and online-payment modes; private and public groups; pending/active membership; missing/found/expired/resolved reports; claimed and unclaimed ownership; single and recurring sessions. Payment, push and deployed-rule parity testing should use authorised staging environments and synthetic accounts, not uncontrolled production experiments.

**Recommended immediate sequence:** confirm and address the permission/entitlement boundaries, repair existing broken journeys, then validate activation and owner value in one focused local pilot. This audit authorises none of those implementation or deployment actions.
