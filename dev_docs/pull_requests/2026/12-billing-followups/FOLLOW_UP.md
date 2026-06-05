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

## Verification

`mix precommit` green — compile (warnings-as-errors), format, credo --strict,
dialyzer (0 errors). `mix test` — 268 tests, 0 failures, 4 skipped.

## Open

None.
