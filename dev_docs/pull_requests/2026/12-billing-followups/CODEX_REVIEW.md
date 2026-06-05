# Codex Review — PR #12 (billing follow-ups)

Reviewer: Codex (GPT-5), 2026-06-05. Scope: `git diff upstream/main...HEAD`
for PR #12 (subscription edit-save payment-method, `format_company_address`
purity, hero icon, `billing_tab!/1` DRY, compat drift test, transactions
row-click guard).

## Findings

- **HIGH** — `web/subscription_form.ex` edit-save payment-method path trusts
  the `payment_method_uuid` from the LiveView event. The selector only renders
  the subscription user's active methods, but a crafted/stale event can submit
  any existing payment-method UUID; `update_subscription/2` only FK-checks it.
  That could attach another user's (or a removed/inactive) payment method to
  the subscription and later charge the wrong token. Validate the UUID against
  the subscription's user + active status before updating.

- **MED** — saving subscription type + payment method is non-atomic:
  `maybe_change_type/2` persists and broadcasts first; if the payment-method
  update then fails, the UI reports failure but the type change already stuck.
  Validate/apply the payment-method change before committing the type change
  (or wrap both in a transaction).

No issues found with `format_company_address/1` purity, the icon change, the
`billing_tab!/1` helper, the compat-delegate drift test, or the transactions
row-click guard.
