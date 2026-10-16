# LocalLink 18.0.5+21 — legacy discovery backfill plan

Status: PASS offline policy/planner; BLOCKED production export, execution and owner decisions. No production records were read or migrated.

The revised planner changes only `discoveryVisibility`. It never writes ownership, memberships, roles, account status, attendee data, entitlements, addresses or coordinates. An index value is not evidence of ownership. Existing underlying privacy fields remain authoritative.

| Record evidence | Proposed handling |
|---|---|
| Established public activity (`everyone`, explicit public intent without a privacy conflict), or a standalone legacy activity under the established default-public contract | Set public canonical discovery value only. Confirm the default-public contract against the approved legacy source/export before execution. |
| Explicit private activity/group, or explicit organisation/group audience with valid context | Set restricted canonical value; retain underlying visibility and ownership. |
| Group explicitly public without contradictory privacy | Set public canonical value; retain ownership and membership. |
| Unknown group visibility, ambiguous linked legacy activity, orphan group context, invalid field types, unknown audience or conflicting privacy flags | **No proposed write.** Retain record unchanged; return manual-review reasons. Do not infer membership or public intent. |
| Already correct canonical value | No write; rerunning is idempotent. |

Dry-run example: four synthetic records, two proposed canonical writes and two unchanged manual-review records. The full record snapshot is returned as a write precondition, with the previous canonical value or field absence recorded for conditional rollback. This output is a plan, not an executable migration.

## Offline dry-run instructions

Use the revised isolated candidate or the approved patched checkout:

```sh
node functions/scripts/plan_discovery_privacy.js exported-records.json > discovery-plan.json
```

Input is an array of `{ "path": "opportunities/id", "data": { ... } }` or organisation-group paths. Preserve Firestore field types in any approved export; timestamps and references need a documented typed export format. Keep exports private. The tool has no Firebase credentials/client, network access or apply mode and rejects unsupported paths and `--apply`. Running it does not authorise an export.

## Required execution design — not implemented or authorised

1. Obtain explicit production-read/export and migration approval; capture collection counts, source revision, typed snapshots, current rules and an immutable reviewed plan hash. Check existing canonical fields for contradictions. Verify established legacy public intent against source evidence rather than weak ownership claims.
2. Stage synthetic and approved representative cases. Verify indexes, public coverage, private exclusions and authoritative permissions. Keep uncertain records in a separate owner-review queue; no automatic default or membership inference.
3. For each approved safe record, transactionally re-read the complete current document and compare its snapshot/update-time precondition. If it changed, disappeared, became uncertain or disagrees with the approved policy, skip and report it. Never replay a stale export or overwrite privacy changes.
4. Write only the approved canonical field. Persist an access-controlled audit receipt with path, policy/source/plan hashes, preconditions, before/after value, operator and transaction result. Retry safely; identical desired values produce no second write. Set strict batch limits and stop on coverage or permission anomalies.
5. Verify public coverage and private exclusion before rule cutover/client readiness. Owner-reviewed decisions need their own reviewed write plan; the planner does not solicit or apply those decisions.
6. Roll back a canonical write only if its receipt and current after-value still match and current privacy permits the restored value. Never restore an unsafe public marker, undo later owner changes or relax rules. For formerly absent fields, conditional field deletion is feasible but may remove public discoverability; assess impact before approval.

The candidate discovery sync re-reads current data transactionally and never changes underlying visibility or membership. It may safely maintain a restricted index value after a later document event; it is not an owner-review decision or permission grant. No migration runner is supplied: production application, audit persistence and recovery rehearsal remain deployment gates.
