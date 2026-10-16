# LocalLink business activation and service reminders

Implemented locally on 9 October 2026 in `/Users/jamesevans/locallink_flutter`. No deployment, upload, production data change or migration was performed. Existing unrelated working-tree changes were preserved.

## Customer experience

Published businesses remain in the existing discovery system regardless of service count. No discovery queries or eligibility rules were loosened.

A claimed listing with an explicit owner can show its existing, valid public phone, email and HTTP(S) website details. These actions open the relevant external application. If the device cannot open the route, the actual contact information appears as selectable text. Unsupported/unsafe URLs and invalid telephone/email values are omitted. Public visibility uses the existing discovery checks, including hidden/private/deleted/moderated records and legacy active defaults.

The previous “Book a service” / “Ask a question” instructions have been replaced with a direct action to view real active services and booking options. Unclaimed listings do not route service enquiries or external contact actions to a moderator or assumed owner. No fake service, new conversation type or automatic owner assignment was introduced.

Where a listing has neither services nor usable contact details, the screen explains that honestly and retains the existing save-business action. There is no fabricated contact route; the owner needs to supply contact details or an appropriate service. Service loading failures also point to available contact details instead of presenting enabled dead-end actions.

## Owner guidance and readiness

The existing dashboard now distinguishes:

- Listing is live.
- Customers can make enquiries, through an existing service enquiry or published contact channel.
- Customers can make bookings, with an active service, usable booking availability, a supported payment method and unrestricted booking access.

Cash and bank transfer are valid payment methods without Stripe. Photos and extra staff do not determine publication or enquiry readiness. Booking readiness checks real direct availability and/or staff slots assigned to active services, including contiguous service duration, booked slots and unexpired locks. It is a snapshot, not a guarantee that a slot remains available until a customer books; existing transaction and payment checks remain authoritative.

Appointment categories receive an actionable “Add your first service” prompt. Owners missing contact information also get a contact-details action while they set up. Trades/service-enquiry categories receive quote/contact guidance and an optional explanation of services. Cafés, shops and unknown categories receive contact/opening-hours guidance rather than a mandatory service requirement. Owners who switch off LocalLink bookings are not automatically nudged to add services.

Conservative automatic-reminder categories: Aesthetics, Beauty, Brows & Lashes, Hair Salon, Barber, Nails, Massage, Skin Clinic, Dog Groomer, Dog Walker, Mobile Valeting and Personal Trainer. Trades such as Gardener, Handyman and Specialist Services are deliberately excluded from automatic reminders. Category policy is implemented in Flutter and the backend; updates should keep both sets aligned and use observed customer journeys rather than broadening reminders indiscriminately.

## Reminder behaviour

Reminders use the existing notification documents, push helper, preferences and router. No email/SMS channel or messaging infrastructure was added.

| Point | Behaviour |
|---|---|
| Immediately after creation | Contextual dashboard guidance; no immediate reminder notification |
| 3 days | First friendly notification |
| 7 days | Differently worded second notification |
| 14 days | Final notification explicitly saying it is the last automatic reminder |
| After final reminder | No further automatic reminders |
| Active service created/restored | Cancel cycle and remove unread reminders for that cycle |
| Service later archived/deleted | Do not automatically restart |
| Owner deliberately opens Add service | May start a fresh cycle if still eligible and no active service exists |
| Ordinary dashboard visit or notification open | Does not enrol legacy listings or restart completed cycles |

The scheduler runs hourly, so delivery is at or after the milestone, normally within the following hour rather than at an exact wall-clock instant. Delayed processing selects only the latest due milestone, avoiding a catch-up burst. A campaign abandoned for 21 days finishes without a stale catch-up reminder.

Eligibility is checked again when processing: explicit claimed owner, active/public business in an appropriate category, registered verified account (verified email or phone provider), enabled account, no moderation ban, booking requests enabled and no active service. Missing/deleted accounts, reassigned ownership, inactive/hidden listings and preference opt-outs suppress further delivery. Moderator-created listings qualify only after genuine claimed ownership is present; an unclaimed listing or its creator alone is insufficient.

Both the existing `reminders` preference and the new `businessSetupReminders` preference must allow delivery. The new setting is visible in Notification settings. Preferences are checked before creating notifications and again immediately before push. The checked-in Firestore rules were extended only to validate this additional owner-only boolean preference; client notification creation and reminder-state access remain denied.

The updated app registers support for the setup notification route through the owner-checked callable. Without that private server-stored capability, no setup reminders are delivered. Registration on a dashboard visit announces route support only, without enrolling or resetting a campaign. Explicit Add service entry registers support and may enrol. These optional calls run without blocking the dashboard/editor and tolerate an older or offline backend.

Reminder IDs include business, cycle and milestone. Notification creation and milestone advancement happen in one transaction. Concurrent workers, retries and deleting an in-app notification do not create duplicate milestone notifications. Push is attempted at most once per claimed milestone; an ambiguous failure is not retried. This trades possible missed push delivery for duplicate prevention while retaining the in-app notification.

## Verification

- Full Flutter suite: **372 tests passed**.
- Backend suite: **173 tests passed**; four emulator tests are skipped in the ordinary run and executed separately below.
- Isolated Firestore emulator: **4 tests passed** using project `demo-locallink-activation` and synthetic data only.
- `flutter analyze --no-pub`: **six pre-existing informational findings**, no warnings/errors; analyzer exits 1 for those infos. No new analyzer findings.
- Function syntax/exports checked; all four activation handlers load.

Tests cover 3/7/14-day boundaries, concurrent/repeated workers, delayed scheduling, final/cancelled campaigns, first active service, later archival, service-creation races, deleted notification records, owner reassignment, anonymous/unverified/disabled/banned accounts, category and public-visibility exclusions, opt-outs, legacy listings, explicit re-entry, unsupported owner-app routes and at-most-once push failure handling. Flutter tests cover discovery without services, independent readiness states, booking duration/staff/lock cases, category guidance, contact validation and device-route fallback. Real-emulator tests establish transaction deduplication, scheduler query compatibility, cancellation, legitimate owner service creation, outsider/anonymous denials, boolean owner-only preferences, and server-only notification/state writes.

No production Auth, Firestore, FCM, payment or device route was exercised. Real iOS/Android external contact applications, push delivery and notification taps still need authorised staging/device verification.

## Files changed

Existing files:

- `firestore.rules` — two additions for the boolean setup-reminder preference.
- `functions/index.js` — wire four activation handlers and the document-written trigger factory.
- `functions/notifications.js` — setup-reminder preference default.
- `lib/models/business_dashboard_model.dart` — independent readiness and contextual next step.
- `lib/services/business_dashboard_service.dart` — contact/payment/readiness and usable booking-time assessment.
- `lib/screens/business_detail_screen.dart` — real service destination, safe contact actions and honest empty/error states.
- `lib/screens/business_home_screen.dart` — contextual guidance, readiness display, refresh after service management and non-enrolling route registration.
- `lib/screens/business_services_screen.dart` — optional explicit setup enrolment on Add service.
- `lib/screens/notification_settings_screen.dart` and `lib/services/notification_preferences.dart` — owner opt-out setting.
- `lib/services/notification_router.dart` — owner-checked service setup destination and safe fallback.

New files:

- `functions/business_activation.js`
- `functions/test/business_activation.test.js`
- `functions/test/business_activation_emulator.test.js`
- `lib/services/business_activation_policy.dart`
- `lib/widgets/business_contact_actions.dart`
- `test/business_activation_test.dart`
- `docs/locallink_business_activation_changes.md` — this implementation and rollout note.

No booking/payment implementation, conversation schema, ownership/claim process, discovery query, existing business document or app version was changed.

## Deployment requirements — not performed

1. Review the targeted change against the intended release baseline. The working tree already contains substantial unrelated changes, including functions and rules; do not deploy the entire working tree without reviewing those changes separately.
2. Deploy the additive notification-preference validation before releasing the new app, so the new toggle can save. No backfill or breaking migration is needed. The private capability document and top-level `businessActivationReminders` collection are server-owned and need no new client access grant.
3. Deploy only the approved activation functions initially with `BUSINESS_SERVICE_REMINDERS_ENABLED` absent or `false`: `beginBusinessServiceSetup`, `onBusinessCreatedServiceSetup`, `onBusinessServiceSetupChanged`, `sendBusinessServiceSetupReminders`. Confirm scheduler permissions and regional configuration. The emulator accepted the existing single-field scheduler query; no additional composite index was introduced.
4. Release the updated app and verify contact fallbacks, dashboard readiness, preference saving, and setup-notification routing on iOS/Android in staging. Capability registration is owner-checked and older backends fail harmlessly.
5. Enable `BUSINESS_SERVICE_REMINDERS_ENABLED=true` in the approved backend environment and redeploy the relevant enrolment/scheduler functions through the normal release process. Review synthetic milestone and cancellation scenarios first. Reminder delivery still requires the owner-app capability.
6. Monitor campaign enrolment, opt-outs, cancellation and scheduler errors. Existing listings are not automatically backfilled; their owners must intentionally enter Add service to start a cycle.

Unresolved limits: no system can retract a push already handed to FCM/OS when a service is created a moment later. Transactions, service-trigger cancellation, unread cleanup and an immediate pre-push check minimise this race and prevent subsequent reminders. At-most-once pushes can be missed after a crash/transport timeout. Category guidance is intentionally conservative and should be validated with representative businesses. A listing with no actual public contact details cannot be made contactable without owner action; the UI now states that honestly.
