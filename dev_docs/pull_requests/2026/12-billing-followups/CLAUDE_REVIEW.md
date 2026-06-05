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

### 3. [OBSERVATION] Non-atomic type + payment-method save
**File:** lib/phoenix_kit_billing/web/subscription_form.ex lines 376–397
**Confidence:** 80/100

Edit-save validates before any write, but the type change and PM change remain
two separate writes; a DB-level failure on the second leaves a committed type
change. Not fixed — a transaction wrapper is invasive because both helpers
broadcast, and the path is `@tag :skip` pending the core `subscription_type_uuid`
gap. Tracked in [FOLLOW_UP.md](FOLLOW_UP.md).

## What Was Done Well

- The edit-save guard validates *before* any write and re-queries the user's
  active methods at save time (not trusting the stale assigned list).
- `save_subscription_edits/3` cleanly threads the two writes through a `with`,
  routing the type change through `change_subscription_type/2` so its broadcast
  still fires.
- The `compat_delegate_test` drift guard is a nice touch for the compat layer.

## Verdict

Approved with fixes — the PR is correct and well-structured; the two follow-up
fixes (status option, create-mode guard) close gaps adjacent to the change.
Compile (`--warnings-as-errors`), `mix format`, and `credo --strict` clean;
DB-backed integration tests require a database not available in the review
environment and should be confirmed green in CI.
