# Follow-up Items for PR #8

Triaged against `main` on 2026-06-04 as part of the quality sweep.
Review: `CLAUDE_REVIEW.md` (2026-05-09) — verdict "Approved (already
merged)" with five prioritized follow-ups.

## Fixed (this sweep — 2026-06-04)

- ~~**Half-translated module surface: `module_stats/0` raw English**~~
  (IMPROVEMENT — HIGH, follow-up #1) — `module_stats/0`
  (`lib/phoenix_kit_billing.ex:140-148`) now wraps each stat label in
  `gettext(...)`: `gettext("Orders")`, `gettext("Invoices")`,
  `gettext("Currencies")`. `permission_metadata/0`
  (`lib/phoenix_kit_billing.ex:128-135`) likewise wraps `label` and
  `description` via `gettext(...)`. The module now uses
  `use Gettext, backend: PhoenixKitBilling.Gettext`
  (`lib/phoenix_kit_billing.ex:44`) so these resolve through the
  module's own catalogue. Commit: *"Address PR review follow-ups
  (i18n, DRY, logging, docs)"*. (Note: the review listed `module_info/0`;
  the actual functions are `module_stats/0` + `permission_metadata/0` —
  there is no `module_info/0`. The raw-English strings it pointed at are
  the ones now wrapped.)

- ~~**Manual `.pot` maintenance not test-guarded against drift**~~
  (IMPROVEMENT — MEDIUM, follow-up #2 partial / #5) — a drift test now
  exists at `test/phoenix_kit_billing/pot_drift_test.exs`
  (`PhoenixKitBilling.PotDriftTest`). It parses `priv/gettext/default.pot`
  and asserts every registered tab label has a `msgid`, closing the
  "added a tab, forgot the catalogue" regression vector the review and
  the `.pot` header both called out.

## Skipped / Deferred (with rationale)

Max is away and granted full autonomy for this sweep. These are
non-blocking DRY / test-breadth improvements safer in a focused PR.

- **13× `gettext_backend:` / `gettext_domain:` boilerplate → `defp
  billing_tab!/1` helper** (IMPROVEMENT — HIGH, follow-up #3) — still
  live: each `Tab.new!` call in `admin_tabs/0` / `settings_tabs/0` /
  `user_dashboard_tabs/0` repeats the two keyword pairs. Pure DRY, no
  behaviour change, but it touches all 13 tab registrations across three
  functions — a structural refactor better landed (and reviewed) on its
  own so a typo doesn't silently drop a backend. Deferred.
- **i18n test only asserts `admin_tabs/0`** (IMPROVEMENT — HIGH,
  follow-up #2 remainder) — `i18n_test.exs` still iterates only
  `admin_tabs/0`; `settings_tabs/0` (1 tab) and `user_dashboard_tabs/0`
  (2 tabs) aren't asserted for `gettext_backend` / `gettext_domain`
  wiring. The new `pot_drift_test.exs` already covers all three
  functions for *label→msgid* coverage, so the practical regression
  (untranslated label) is guarded; extending the wiring assertion to all
  three functions is a small test addition deferred alongside the
  `billing_tab!/1` helper it naturally pairs with.
- ~~**Track the 23-file LiveView body-string migration** (IMPROVEMENT —
  LOW, follow-up #4)~~ — **CORRECTION (2026-06-05): this is already done.**
  Re-checked against current code: 20 of the web LVs already
  `use Gettext, backend: PhoenixKitBilling.Gettext`, and billing's et/ru
  catalogues are ~fully populated (582/582). The original note was stale.
  The only files still on `PhoenixKitWeb.Gettext` are the 4 **print views**
  (`*_print.ex`), and those render **hardcoded English** (zero `gettext`
  calls) — i.e. full print-view i18n is a *separate, never-started feature*,
  not a backend-routing migration. Two real items surfaced for Max:
  (a) print views are not internationalised at all; (b) `default.pot` is
  **stale** — `mix gettext.extract` wants ~65 msgids (mostly from
  `errors.ex`) and a blind `mix gettext.merge` fuzzy-corrupts ~5 `en`
  entries, so it needs a careful extract + native et/ru pass.
- **`gettext` as a runtime application** (IMPROVEMENT — LOW) — benign;
  core already boots `:gettext`. No action.
- **mix.lock dep bumps incl. `decimal` 2.x → 3.x** (IMPROVEMENT —
  MEDIUM) — water under the bridge per the review (the follow-up "lib
  upgrades" commit already absorbed them). Future-hygiene note only.
- **Nitpicks** (CHANGELOG/version bundling, `I18nTest` vs `GettextTest`
  naming, the unknown-locale test, self-alias) — cosmetic; left as-is.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_billing.ex` | `module_stats/0` + `permission_metadata/0` strings wrapped in `gettext/1`; `use Gettext, backend: PhoenixKitBilling.Gettext` |
| `test/phoenix_kit_billing/pot_drift_test.exs` | Drift guard: every registered tab label has a `default.pot` msgid (all 3 tab functions) |

## Verification

`mix precommit` green (compile / format / credo --strict / dialyzer 0
errors). `mix test` — 177 tests, 0 failures, 3 skipped (the 3 skips are
the core `subscription_type_uuid` column gap documented in the module
`AGENTS.md`). `pot_drift_test.exs` passes.

## Open

None. The `billing_tab!/1` DRY helper + wider wiring assertion were done in
PR #12. The "23-file body-string migration" was a stale note — the LV body
strings already route through the module backend (see correction above).
Remaining (surfaced for Max, separate efforts): print-view i18n (hardcoded
English) and a careful `default.pot` refresh + native translation pass.
