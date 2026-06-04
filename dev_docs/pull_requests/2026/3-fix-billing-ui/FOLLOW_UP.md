# Follow-Up: PR #3 — Post-merge issues and action items

**Created:** 2026-03-30
**Updated:** 2026-06-04 (quality-sweep re-triage against current `main`)
**Source:** [CLAUDE_REVIEW.md](CLAUDE_REVIEW.md)

## Fixed (pre-existing — in original follow-up commits)

- ~~**PaymentMethod schema field mismatch**~~ — `label` → `display_name`
  to match the V33 DB column (review #2).
- ~~**Removed all try/rescue blocks** in `subscription_form.ex`~~ — they
  were masking the schema mismatch (review #2).
- ~~**Hardcoded EUR fallback**~~ → now uses
  `Settings.get_setting("billing_default_currency", "EUR")` (review #3).
- ~~**`last_renewal_error` not castable**~~ → added to the subscription
  changeset cast list (review #4).
- ~~**Cancel flash message inconsistency**~~ → edit form now says "will
  be cancelled at period end" (review #6).
- ~~**Missing `data-confirm` on pause/cancel buttons**~~ → added
  (review #6/#12).
- ~~**Duplicated `status_badge_class/1` + `format_interval/2`**~~ →
  extracted to `SubscriptionHelpers` (review #7).
- ~~**`admin_locale_routes/0` copy-paste of `admin_routes/0`**~~ →
  refactored into `build_admin_routes/1` (review #8).
- ~~**Duplicate `alias Routes`**~~ → removed in `subscription_form.ex`,
  `subscription_detail.ex`, `subscription_types.ex` (review #9).

## Skipped / Deferred (with rationale)

Max is away and granted full autonomy for this sweep. Each item below is
a **behavioral or structural change**, not a correctness bug — the
remaining `## Remaining items` from the original follow-up were
re-verified against current code and confirmed still live. They are
safer reviewed in a focused PR than folded into a quality sweep.

- **`update_subscription/2` accepts arbitrary attrs with no guard**
  (review #19, MEDIUM) — verified still live:
  `lib/phoenix_kit_billing.ex:2976-2980` passes any `attrs` map straight
  into `Subscription.changeset/2`, which casts `status`, `user_uuid`,
  and other state-machine fields. The dedicated lifecycle functions
  (`pause_subscription`, `resume_subscription`, `cancel_subscription`)
  exist precisely to gate those transitions; `update_subscription/2`
  bypasses them. Fixing this means introducing a restricted
  `admin_changeset` (or narrowing the cast list) and re-pointing callers
  — a behavioral change to the public context API that wants its own PR
  and its own tests. **Deferred to a focused PR**; surfaced for Max.
- **`extend_subscription` hardcoded to 30 days** (review #11) — verified
  still live: `subscription_form.ex:311` does
  `DateTime.add(sub.current_period_end, 30, :day)` (and the flash at
  `:317` says "extended by 30 days") regardless of the subscription
  type's interval (could be weekly/yearly). Correct behavior is to
  extend by the type's actual interval or accept an admin-specified
  count — a UX/semantics change, deferred for a deliberate review.
- **Status actions redirect away from the edit form** (review #13) —
  verified still live: each status action `push_navigate`s back to the
  detail page (`subscription_form.ex` status handlers), so an admin
  pausing *and* changing a plan has to re-enter the edit form. Reloading
  in-place is a non-trivial LV-flow change; deferred.
- **Edit save only handles plan-type change** (review #10) — payment
  method changes are still ignored in edit mode while the button says
  "Save Changes". Behavioral scope expansion; deferred (pairs naturally
  with the `update_subscription/2` guard work above).
- **No tests for compat modules** (review #14) — the `compat/*.ex`
  delegates are runtime delegation with no drift guard. Adding delegation
  tests (or a `defoverridable`/auto-`@impl` macro per review #5) is a
  test-infrastructure addition; deferred. The compat layer's removal
  condition is documented in `mix.exs` (see PR #5 follow-up).
- **Inconsistent row-click behavior across list pages** (review #16) —
  profiles → edit, invoices/subscriptions/orders → detail, currencies →
  none. Picking one pattern is a UX-consistency decision spanning ~6
  LiveViews; deferred for Max's call on which pattern wins.
- **Compat-removal tracking ticket** (review #15) — the removal
  condition now lives in the `mix.exs` comment (added in the PR #5
  follow-up). A standalone GitHub issue is the boss's to file.

## Corrections to original review (retained)

- **Issue #1 retracted** — subscription columns (`plan_name`, `price`,
  `currency`, etc.) already exist from PhoenixKit core V33; the PR
  correctly added them to the Elixir schema only.
- **Issue #2 root cause** — not a missing `label` migration; the
  PaymentMethod schema declared `field(:label)` while the DB column is
  `display_name`.
- **Issue #6 re-evaluated** — both list and edit call
  `cancel_subscription/1` with the same defaults; the only divergence
  was the flash message text.

## Verification

`mix precommit` green (compile / format / credo --strict / dialyzer 0
errors). `mix test` — 177 tests, 0 failures, 3 skipped (the 3 skips are
the core `subscription_type_uuid` column gap documented in the module
`AGENTS.md`).

## Open

None as parked work. The six Deferred items above are surfaced for Max
as candidates for a focused subscription-admin follow-up PR — they are
behavioral/structural changes deliberately kept out of the quality
sweep, not silently shelved.
