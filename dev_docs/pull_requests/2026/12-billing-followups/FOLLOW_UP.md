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

## Post-merge review (2026-06-05, Claude)

A follow-up review of the merged PR surfaced two issues in the same area and
fixed them:

- **BUG — `list_payment_methods/2` silently ignored the `status:` option.**
  Every caller (the new edit-save guard, the form, and the new scoping test)
  passes `status: "active"`, but the function only read `:active_only`
  (default `true`). It worked *by accident* — `status:` was a dead option, and
  `list_payment_methods(u, status: "removed")` would still have returned active
  methods. `lib/phoenix_kit_billing.ex` now honours an explicit `status:`
  (exact-status filter) and keeps `active_only` as the backward-compatible
  fallback.

- **SECURITY (symmetry) — create mode was still unguarded.** The edit-save
  guard rejected a crafted/stale `payment_method_uuid`, but the identical
  client-event vector existed in *create* mode (`create_subscription/2` only
  FK-checks the UUID). `validate_payment_method/2` was refactored to key on
  `user_uuid` and the same pre-write guard now runs in the create branch;
  create-mode `payment_method_uuid` also flows through `normalize_uuid/1`.

### Tests

- Tightened the `list_payment_methods/2` scoping test to pattern-match
  contents+count, and added a test that pins `status:` filtering (queries
  `"removed"` directly) so the option can't silently regress again.

## Open

- **Non-atomic type + payment-method save (minor).** Edit-save validates
  before any write, but the type change and PM change are still two separate
  writes; a DB-level failure on the second leaves a committed type change.
  Deferred — a transaction wrapper is invasive because both helpers broadcast,
  and the path is `@tag :skip` pending the core `subscription_type_uuid` gap.
