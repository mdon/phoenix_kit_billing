# Follow-up Items for PR #12

Source: [CODEX_REVIEW.md](CODEX_REVIEW.md) (Codex, 2026-06-05). Both findings
were addressed in this PR.

## Fixed (this PR)

- ~~**HIGH — edit-save trusts the client payment_method_uuid**~~ —
  `web/subscription_form.ex` now validates the submitted UUID up front via
  `validate_payment_method/2`: it must be one of the subscription user's own
  **active** methods (`Billing.list_payment_methods(user_uuid, status:
  "active")`), otherwise the save returns `{:error, :payment_method_not_usable}`
  and writes nothing. `nil` (clearing the method) is still allowed. A crafted
  or stale event can no longer attach another user's / a removed / inactive
  payment token. Commit *"Validate edit-save payment method against the
  subscription's user"*.

- ~~**MED — non-atomic type + payment-method save**~~ — the validation runs as
  the **first** step of the `with` in `save_subscription_edits/3`, before
  `maybe_change_type/2`. An invalid/forbidden payment method therefore fails
  *before* the type change is committed, closing the "type stuck, PM failed"
  window the review described. (A full DB transaction across
  `change_subscription_type/2` — which broadcasts — and `update_subscription/2`
  was deliberately avoided: broadcasting inside a transaction is an
  anti-pattern. Validating-before-write covers the realistic failure mode.)

## Tests

- `test/phoenix_kit_billing/integration/context_test.exs` — added a
  `list_payment_methods/2` scoping test (user-scoped + active-only), pinning
  the property the guard relies on. (A full edit-save LV test remains
  `@tag :skip` behind the core `subscription_type_uuid` column gap — see
  core PR #583.)

## Post-merge review (2026-06-05, Claude) — fixed in commit 356a195

See [CLAUDE_REVIEW.md](CLAUDE_REVIEW.md) for the full write-up. Two adjacent
bugs were discovered and fixed:

- **BUG — `list_payment_methods/2` ignored the `status:` option** (read only
  `:active_only`; worked by the default). Now honours an explicit `status:`.
- **SECURITY — create mode lacked the edit-mode payment-method guard.**
  `validate_payment_method/2` now keys on `user_uuid` and runs in both paths.

Tests: tightened the scoping test to pattern-match contents+count; added a
`status:`-filtering test so the option can't silently regress.

## High-effort review (2026-06-05, Claude) — `/code-review high`

A high-effort multi-angle pass over the post-merge fixes found no correctness
bugs in the refactor and surfaced one altitude finding + two nitpicks, all
fixed:

- **Ownership guard moved into the context.** The payment-method
  ownership/active check lived only in `SubscriptionForm`; the public
  `create_subscription/2` and `update_subscription/2` only FK-checked the UUID,
  so the invariant was bypassable by any non-form caller (latent — no current
  exploit path). Added `ensure_payment_method_usable/2` as the first step of
  both context functions → single non-bypassable enforcement point. Form guards
  retained as a UX/fail-fast layer. New reject-path context tests don't need the
  `subscription_type_uuid` skip (the guard short-circuits before any insert).
- **Nitpick:** `normalize_uuid` was computed twice on the create-mode happy
  path → bound once.
- **Nitpick:** redundant `refute` in the scoping test → dropped.

**For other agents:** new callers of `create_subscription/2` /
`update_subscription/2` no longer need to validate payment-method ownership
themselves — the context rejects a foreign/inactive UUID with
`{:error, :payment_method_not_usable}`.

## Open

- **Non-atomic type + payment-method save (minor).** Edit-save validates
  before any write, but the type change and PM change are still two separate
  writes; a DB-level failure on the second leaves a committed type change.
  Deferred — a transaction wrapper is invasive because both helpers broadcast,
  and the path is `@tag :skip` pending the core `subscription_type_uuid` gap.
