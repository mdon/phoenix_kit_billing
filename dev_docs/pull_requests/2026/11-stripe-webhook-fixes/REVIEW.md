# Post-merge Review of PR #11 — "Fix Stripe/webhook bugs + quality sweep"

Reviewed on 2026-06-04 against `main` (PR #11 already merged) using the
Elixir / Phoenix / Ecto thinking skills. The three core bug fixes
(webhook struct bracket-access, `billing_stripe_secret_key` fallback,
`unique_constraint` name pinning) are correct, and the new test harness
is solid. The findings below are follow-ups surfaced by the review.

Fixes were applied on branch `review/pr11-followups`. Verification:
`mix compile --warnings-as-errors`, `mix format --check-formatted`, and
`mix credo --strict` are all green; `mix test` runs the pure suite (DB
not available in the review sandbox) — `errors_test.exs` 65 tests, 0
failures. The DB-backed suites should be re-run on a host with Postgres.

---

## Fixed (this review — 2026-06-04)

### 1. `Errors` module was dead code — never wired into any call site (HIGH)

The PR introduced `PhoenixKitBilling.Errors` (61 atom→message mappings +
63 tests) whose moduledoc states *"Anything user-facing (flash messages,
error banners) goes through `message/1`."* In practice there were **zero**
callers of `Errors.message/1` in `lib/`. Every flash still did
`inspect(reason)`, e.g. `subscription_form.ex`:

```elixir
gettext("Failed to cancel: %{reason}", reason: inspect(reason))
```

so a user hitting `:has_active_subscriptions` saw the literal flash
**"Failed to cancel: :has_active_subscriptions"** — a raw, untranslated
atom with a leading colon.

**Fix:** wired `Errors.message(reason)` into all 15 user-facing
`{:error, reason}` flash/error-assign sites across `web/`:

- `subscription_form.ex` (6 sites) — `alias PhoenixKitBilling.Errors` added
- `subscription_detail.ex` (5 sites) — alias added
- `subscription_types.ex` (2 sites) — alias added
- `subscriptions.ex` (1 site) — alias added
- `subscription_type_form.ex` (1 site) — alias added

To make the helper safe at sites whose `reason` can be either a domain
atom *or* an `%Ecto.Changeset{}` (e.g. `change_subscription_type/3`),
`Errors.message/1` gained an `%Ecto.Changeset{}` clause that formats
errors as `"field: message; ..."` (mirrors the existing
`format_changeset_errors/1`). `Logger` `inspect/1` calls were left
unchanged (developer-facing, not user-facing).

### 2. Webhook retry cap never enforced — unbounded retries + dead helpers (HIGH)

`WebhookEvent.retriable?/1` and `max_retries_exceeded?/1` (both gated on
`count >= 5`) were defined and tested but **never called**. The
processor's idempotency branch returned `{:retry, existing}` for any
unprocessed event regardless of `retry_count`, so a permanently-failing
event would be reprocessed on every provider redelivery forever, with
`retry_count` climbing unbounded.

**Fix:** `webhook_processor.ex` `upsert_webhook_event/1` now consults
`WebhookEvent.max_retries_exceeded?/1` in its `cond` and returns a new
`{:max_retries, existing}` tuple; `process/2` logs and returns
`{:error, :max_retries_exceeded}` instead of reprocessing. Added the
`:max_retries_exceeded` atom to `Errors` (type + message + test).

### 3. `extend_subscription` crashed on a nil billing period (MEDIUM)

`subscription_form.ex` did `DateTime.add(sub.current_period_end, days, :day)`
with no guard. For a subscription whose `current_period_end` is `nil`
(trialing / freshly created), `DateTime.add/3` raised `FunctionClauseError`,
crashing the LiveView event rather than showing the "Failed to extend" flash.

**Fix:** added a guarded `handle_event("extend_subscription", ...)` head
matching `current_period_end: nil` that assigns a friendly error instead
of crashing.

### 4. `Stripe.available?/0` could return `nil`, violating its `:: boolean()` contract (MEDIUM)

```elixir
config[:enabled] && config[:api_key] && config[:api_key] != ""
```

returns `nil` (not `false`) when `api_key` is `nil`, but the behaviour
declares `@callback available?() :: boolean()`.

**Fix:** rewrote as
`config[:enabled] and is_binary(config[:api_key]) and config[:api_key] != ""`
in both `available?/0` and (for consistency) `ensure_configured/0`.

### 5. Stale Stripe moduledoc would mislead integrators (MEDIUM)

The `@moduledoc` documented a `{:stripe, "~> 1.1"}` hex dependency and a
`PhoenixKitBilling.update_provider_config(:stripe, %{api_key: ...})` API.
Neither exists — the module talks to the Stripe REST API directly via
`Req`, and config lives in `PhoenixKit.Settings` keys
(`billing_stripe_secret_key`, `billing_stripe_webhook_secret`,
`billing_stripe_enabled`). Notably this is the very key-name mismatch the
PR just fixed.

**Fix:** rewrote the Configuration and Dependencies sections to document
the actual `Settings`-based config and the no-`stripe`-package reality.

### 6. `SubscriptionType` interval `case` had no catch-all (LOW / defensive)

`billing_period_days/1` and `next_billing_date/2` matched only
`"day"/"week"/"month"/"year"`. Safe today (changeset validates inclusion)
but an unvalidated struct or future interval value would `CaseClauseError`.

**Fix:** added `_ ->` fallbacks that degrade to a monthly cadence.

### 7. Receipt failures silently discarded in the webhook path (LOW)

`process_invoice_payment/2` called `Billing.generate_receipt/1` and
`Billing.send_receipt/2` and ignored their `{:ok, _} | {:error, _}`
returns, so a failed receipt was invisible.

**Fix:** extracted `maybe_generate_and_send_receipt/1`, which keeps the
best-effort behaviour (a receipt failure must not fail an already-succeeded
payment) but `Logger.warning`s non-`:ok` results.

---

## Noted, intentionally not changed

- **`Activity.log/2`'s broad `rescue e`** (`activity.ex`) is deliberate —
  logging must never crash the caller. Flagged only for awareness: it is
  the one place a genuine programming error in metadata construction is
  downgraded to a warning. Left as-is.

- **Two `format_changeset_errors/1` copies** remain in `subscription_form.ex`
  and `order_detail.ex` for inline form rendering. `Errors.message/1` now
  carries an equivalent changeset formatter; a future cleanup could collapse
  all three onto `Errors`. Left out of this pass to keep the diff focused.

## Deferred from PR #11 itself (still open, per its description)

- Core bug: fresh `ensure_current/2` builds miss
  `phoenix_kit_subscriptions.subscription_type_uuid` (core migration V65
  renames a column V33 never creates). 3 tests remain `@tag :skip` pending
  a core fix — outside this repo.
- Remaining raw `<input>/<select>` (filter/dynamic/checkbox inputs and the
  customer/line-item selects) not yet migrated to core components.
