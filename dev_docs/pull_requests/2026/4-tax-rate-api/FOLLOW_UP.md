# Follow-up Items for PR #4

Triaged against `main` on 2026-06-04 as part of the quality sweep.

## No findings

`CLAUDE_REVIEW.md` (claude-opus-4-6, 2026-03-30) flagged three bugs and
two soft observations. Re-verified against current `lib/phoenix_kit_billing.ex`:
all three bugs were already fixed before this sweep, and both observations
are non-actionable.

- ~~**#1** `get_tax_rate_percent/0` ignores `tax_enabled?` flag~~ — FIXED
  pre-existing. `get_tax_rate_percent/0` (`lib/phoenix_kit_billing.ex:395-413`)
  now wraps its body in `if tax_enabled?()` and returns `0` when tax is
  disabled, mirroring `get_tax_rate/0`.
- ~~**#2** `get_tax_rate/0` crashes on non-numeric settings values~~ — FIXED
  pre-existing. `get_tax_rate/0` (`lib/phoenix_kit_billing.ex:372-390`) now
  uses `Decimal.parse/1` with an `:error` branch that logs a warning and
  falls back to `Decimal.new("0")` rather than raising `Decimal.Error`.
- ~~**#3** `get_config/0` duplicates `tax_enabled?/0` logic~~ — FIXED
  pre-existing. `get_config/0` (`lib/phoenix_kit_billing.ex:346`) calls
  `tax_enabled?()` instead of inlining the settings comparison.
- **#4** Compat module adds `get_config/0` delegate — OBSERVATION only.
  The delegate is correct (the compat module fully delegates the public
  API as of PR #5); no action.
- **#5** `get_tax_rate/0` doc mentions implementation details — NITPICK.
  The doc is accurate and stable; left as-is.

## Verification

`mix precommit` green (compile / format / credo --strict / dialyzer 0
errors). `mix test` — 177 tests, 0 failures, 3 skipped (the 3 skips are
the core `subscription_type_uuid` column gap documented in the module
`AGENTS.md`, unrelated to this PR).

## Open

None.
