# PR #7 (phoenix_kit_billing) — feat: add widgets

**Author:** @mithereal (Jason Clark) · **Branch:** `main` → `main` · **Files:** 3 (+231 / −0)

## Summary

Adds `Framework.Billing.Widgets` with four billing dashboard widgets (active subscriptions, MRR, failed payments, churn rate). Adds `:number` and `:ex_cldr_currencies` hex dependencies. README update.

This PR is the billing side-car to phoenix_kit #488 (Advanced User Dashboard), which introduced the widget system. Since #488 hasn't merged (and has blocking issues), this PR has no integration path yet.

## Overall verdict

**Do not merge as-is.** Multiple bugs including wrong module namespace (won't compile as part of phoenix_kit_billing), likely nonexistent field references in queries, undefined helper `RepoHelper`, and heavy new dependencies for a minimal feature. Needs rework once #488's widget contract is finalised.

## Findings

### BUG — CRITICAL

- **Wrong module namespace.** `defmodule Framework.Billing.Widgets` is inconsistent with every other module in this package (all use `PhoenixKitBilling.*`). This module won't be reachable via the expected `PhoenixKitBilling.Widgets` call. Should be `defmodule PhoenixKitBilling.Widgets`.

- **`RepoHelper.repo()` is undefined.** This function doesn't exist anywhere in phoenix_kit_billing (or phoenix_kit). All other context modules access the configured repo via `Application.get_env/3` or by accepting a `repo` option. This will cause a compile error or `UndefinedFunctionError` at runtime.

- **`Cldr.Currency.symbol/1` is called outside the `try` block** in `get_mrr/1`. If `PhoenixKitBilling.get_default_currency/0` returns an unexpected value or Cldr is not configured, this crashes before the rescue can catch it. Move it inside the `try`, or call it defensively.

### BUG — HIGH

- **`s.created_at` in churn rate query** — `PhoenixKit.Billing.Subscription` uses `timestamps()` which generates `inserted_at` / `updated_at`. `created_at` is not a field in the schema. This query will fail at compile time (Ecto query macro validation).

- **`s.cancelled_at` and `s.status == :cancelled`** — `cancelled_at` may not exist as a field in `PhoenixKit.Billing.Subscription`. Verify the schema fields before using them in queries.

- **`from(... select: s.amount_cents)` combined with `repo.aggregate(..., :sum, :amount_cents)`** — the `select` is ignored by `aggregate/3`. Harmless but misleading; remove the `select` clause.

### IMPROVEMENT — HIGH

- **PR is tightly coupled to unmerged #488.** The widget struct/protocol defined in #488 (which is itself not ready to merge) defines what `widgets/0` should return. The shape here (`id`, `title`, `value: fn`, `roles`, `description`) may or may not match the final widget contract. This whole module should be written after the widget API is stabilised.

- **New dependencies (`:number`, `:ex_cldr_currencies`) are heavy for the use case.** `Number.Currency.number_to_currency/2` and `Number.Percentage.number_to_percentage/1` could be replaced with a simple `"#{Float.round(x, 2)}"` or the already-present Cldr formatting, avoiding 2 new transitive deps.

### BUG — MEDIUM

- **Churn rate query counts "subscriptions at start of month" incorrectly.** The query is:
  ```elixir
  where: s.created_at <= ^month_start or s.status == :active
  ```
  This counts all currently active subscriptions AND any ever-created before month start — mixing historical and current state. A correct baseline is: subscriptions that existed at `month_start` (i.e., `inserted_at < month_start AND status not :cancelled_before_month_start`). The current query will overcount.

- **`end_of_month` returns `~T[23:59:59]`** which misses the last second of the day. Use `Date.end_of_month/1` + `DateTime.new!(date, ~T[23:59:59.999999])` or query with `< beginning_of_next_month`.

### NITPICK

- Outer `@doc` on private functions (`defp get_active_subscriptions` etc.) — `@doc` has no effect on private functions. Remove or convert to `#` comments.
- `enabled?/1` takes a `user` param but ignores it. If it's always module-level availability, the param adds confusion.
- No tests.

## Recommendation

Request changes. Minimum to land:

1. Rename module to `PhoenixKitBilling.Widgets`.
2. Replace `RepoHelper.repo()` with the pattern used elsewhere in this package.
3. Fix `created_at` → `inserted_at`, verify `cancelled_at` exists.
4. Move `Cldr.Currency.symbol/1` call inside the `try`.
5. Remove the `select` clause from the MRR query.
6. Wait for phoenix_kit #488's widget API to be finalised before merging.

Additionally: evaluate dropping `:number` / `:ex_cldr_currencies` in favour of simpler formatting.
