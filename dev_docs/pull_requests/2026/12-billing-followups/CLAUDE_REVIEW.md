# Code Review: PR #12 — Billing follow-ups: edit-save payment method + PR-review cleanups

**Reviewed:** 2026-06-05
**Reviewer:** Claude (claude-opus-4-8)
**PR:** https://github.com/BeamLabEU/phoenix_kit_billing/pull/12
**Author:** Max Don (mdon)
**Head SHA:** fa73ab0
**Status:** Merged

## Summary

Clears deferred items from the PR #3/#5/#8 quality sweep: fixes edit-save
dropping payment-method changes (the selector was hidden in edit mode and the
save path only ran `change_subscription_type/2`), adds a security guard
validating the submitted `payment_method_uuid` against the subscription user's
own active methods, fixes an invoice-less transaction row navigating to a
broken URL, and a set of safe cleanups (pure `format_company_address/1`, hero
icon, `billing_tab!/1` DRY, compat-delegate drift test).

The core change is sound. Reviewing the same area surfaced two further issues,
both fixed in commit 356a195.

## Issues Found

### 1. [BUG - HIGH] `list_payment_methods/2` silently ignored the `status:` option — FIXED
**File:** lib/phoenix_kit_billing.ex lines 3162–3179 (pre-fix)
**Confidence:** 95/100

Every caller — the new edit-save guard, the form's `handle_params`, and the
new scoping test — passes `status: "active"`, but the function only read
`Keyword.get(opts, :active_only, true)`. The `status:` key was never inspected,
so it worked *by accident* via the `active_only` default; `status: "removed"`
would still have returned active methods. The PR's own "scoping" test passed
because of the default, not the option, giving false confidence. Fixed to
honour an explicit `status:` (exact-status filter) with `active_only` kept as
the backward-compatible fallback.

### 2. [BUG - MEDIUM] Payment-method security guard not mirrored in create mode — FIXED
**File:** lib/phoenix_kit_billing/web/subscription_form.ex lines 208–258 (pre-fix)
**Confidence:** 90/100

The PR added a guard rejecting a crafted/stale `payment_method_uuid` in edit
mode, but the identical client-event vector (`select_payment_method` stores any
submitted UUID) existed in *create* mode, where `create_subscription/2` only
FK-checks the UUID — no user/active scoping. A crafted event could attach
another user's payment method to a new subscription. Fixed by refactoring
`validate_payment_method/2` to key on `user_uuid` and running the same
pre-write guard in the create branch; create-mode `payment_method_uuid` now
also flows through `normalize_uuid/1`.

### 3. [BUG - MEDIUM] Ownership guard lived in the web layer; context was bypassable — FIXED
**File:** lib/phoenix_kit_billing.ex lines 2856 (`create_subscription/2`), 2992 (`update_subscription/2`)
**Confidence:** 85/100

Surfaced by the high-effort second-pass review (2026-06-05). The
payment-method ownership/active guard added in this PR lived **only** in
`SubscriptionForm` (`validate_payment_method/2`). The public, compat-delegated
context functions `create_subscription/2` and `update_subscription/2` only
FK-checked `payment_method_uuid` (`schemas/subscription.ex:156` —
`foreign_key_constraint`, which proves existence, not ownership). No current
caller exploited it (latent), but any future controller / checkout LiveView /
API endpoint / host-app call could attach another user's or an
inactive/removed method, which the renewal worker would later charge. Fixed by
adding a context-level `ensure_payment_method_usable/2` guard run as the first
step of both functions — a single non-bypassable enforcement point. The form
guards are kept as a fast UX pre-check (and, in edit mode, to fail before the
type change commits). Returns the existing `:payment_method_not_usable`
(errors.ex:173, "This payment method cannot be used.").

### 4. [NITPICK] `normalize_uuid` computed twice on the create-mode happy path — FIXED
**File:** lib/phoenix_kit_billing/web/subscription_form.ex lines 209–235

`normalize_uuid(pm_uuid)` ran once in the cond guard and again building attrs —
a drift hazard if the two ever diverged (guard validates X, persist Y). Fixed
by binding `pm_uuid = normalize_uuid(pm_uuid)` once right after destructuring.

### 5. [NITPICK] Redundant assertion in scoping test — FIXED
**File:** test/phoenix_kit_billing/integration/context_test.exs line 423

`refute pm_b.uuid == only_uuid` could never fail given the preceding exact
single-element pattern-match + `only_uuid == pm_a.uuid`. Dropped; added a
comment explaining what the pattern-match already pins, and a comment on the
`_pm_b` fixture stating its purpose (it must never appear in user_a's list).

### 6. [OBSERVATION] Non-atomic type + payment-method save (still open)
**File:** lib/phoenix_kit_billing/web/subscription_form.ex lines 376–397
**Confidence:** 80/100

Edit-save validates before any write, but the type change and PM change remain
two separate writes; a DB-level failure on the second leaves a committed type
change. Not fixed — a transaction wrapper is invasive because both helpers
broadcast, and the path is `@tag :skip` pending the core `subscription_type_uuid`
gap. Tracked in [FOLLOW_UP.md](FOLLOW_UP.md).

> **Note for other reviewers/agents.** `list_payment_methods/2` honours an
> explicit `status:` (exact-status filter) and falls back to `active_only`
> (default `true`) — pass `status: "active"` for the common case. The
> payment-method ownership/active rule is now enforced in the **context**
> (`ensure_payment_method_usable/2` in lib/phoenix_kit_billing.ex), so you do
> **not** need to re-validate in new callers of `create_subscription/2` /
> `update_subscription/2`; they reject a foreign/inactive UUID with
> `{:error, :payment_method_not_usable}`. The form's `validate_payment_method/2`
> is now just a UX/fail-fast layer, not the security boundary. The new
> reject-path context tests (context_test.exs) run without the
> `subscription_type_uuid` skip because the guard short-circuits before any
> insert; the happy-path subscription tests are still `@tag :skip` pending
> core PR #583.

## What Was Done Well

- The edit-save guard validates *before* any write and re-queries the user's
  active methods at save time (not trusting the stale assigned list).
- `save_subscription_edits/3` cleanly threads the two writes through a `with`,
  routing the type change through `change_subscription_type/2` so its broadcast
  still fires.
- The `compat_delegate_test` drift guard is a nice touch for the compat layer.

## Verdict

Approved with fixes — the PR is correct and well-structured. Follow-up fixes
across two review passes closed the adjacent gaps: the `status:` option
(#1), the create-mode guard (#2), and — from a high-effort second pass —
pushing the ownership guard down into the context so it is no longer
bypassable (#3), plus two nitpick cleanups (#4, #5). Only the non-atomic
edit-save (#6) remains open, deliberately deferred. Compile
(`--warnings-as-errors`), `mix format`, and `credo --strict` clean; DB-backed
integration tests (including the new context guard tests) require a database
not available in the review environment and should be confirmed green in CI.
