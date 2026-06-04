# Follow-up Items for PR #5

Triaged against `main` on 2026-06-04 as part of the quality sweep.
Reviews: `CLAUDE_REVIEW.md` (Claude Sonnet 4.6), `MISTRAL_REVIEW.md`,
`PINCER_REVIEW.md` (all 2026-04-06). The three reviews overlap heavily;
findings are consolidated by topic below.

## Fixed (this sweep — 2026-06-04)

- ~~**`get_company_info` duplicated across 4 print views**~~
  (CLAUDE #3, PINCER #1, MISTRAL "Consolidation") — the four print
  LiveViews (`invoice_print.ex`, `receipt_print.ex`,
  `credit_note_print.ex`, `payment_confirmation_print.ex`) each carried
  an identical private `get_company_info/0` that called
  `Organization.get_company_info()` + `Organization.get_bank_details()`
  inline. Extracted to a single public
  `PhoenixKitBilling.get_company_info/0`
  (`lib/phoenix_kit_billing.ex:3447-3459`); all four views now call
  `Billing.get_company_info()`. Removes the 4× copy-paste and the direct
  print-view→core-settings-module coupling the reviews flagged. Commit:
  *"Address PR review follow-ups (i18n, DRY, logging, docs)"*.

## Fixed (pre-existing)

- ~~**Alias round-trip noise in git history**~~ (CLAUDE #1) — historical
  git-history observation, not a code defect. The final state is correct
  (`PhoenixKit.Utils.CountryData`, `lib/phoenix_kit_billing.ex:50`).
  Nothing to change.
- ~~**`ignore_module_conflict: true` is global**~~ (CLAUDE #2, MISTRAL,
  PINCER #3) — accepted as a documented transitional measure. The
  `mix.exs:13-19` comment now spells out the intent **and** the removal
  condition ("drop this once core no longer ships the old
  `PhoenixKit.Modules.Billing` namespace; then delete compat/billing.ex
  too"), which is exactly the TODO/tracking note the reviews asked for.
  Comment expanded in commit *"Address PR review follow-ups"*.

## Skipped / Deferred (with rationale)

Max is away and granted full autonomy for this sweep. The items below
are minor or behavioral-design changes that are safer reviewed in a
focused PR than folded into a quality sweep; none is a correctness bug.

- **`module_stats/0` not annotated `@impl PhoenixKit.Module`** (CLAUDE
  #5, PINCER #2) — **N/A, not deferred.** Verified `module_stats/0` is
  **not** a declared callback on the `PhoenixKit.Module` behaviour
  (checked `phoenix_kit/lib/phoenix_kit/module.ex` `@callback` list —
  it declares `module_key`, `module_name`, `version`, `admin_tabs`,
  `settings_tabs`, `permission_metadata`, etc., but no `module_stats`).
  Adding `@impl PhoenixKit.Module` would therefore be **wrong** — the
  compiler would warn "module attribute @impl was set but no behaviour
  specifies such callback". `module_stats/0` is an informal convention
  read reflectively by the admin Modules card. Left without `@impl`,
  which is correct. (The review's own conditional — "if `PhoenixKit.Module`
  does define it" — resolves to *it does not*.)
- **`module_stats/0` / `get_config/0` perform DB queries with no
  caching** (CLAUDE #4, MISTRAL "Performance") — accurate; `module_stats/0`
  → `get_config/0` runs three count queries. Scoped to the once-per-render
  admin Modules card, so no live N+1. A docstring cost-note or caching
  layer is a behavioral change; deferred to a focused PR rather than
  added blind during the sweep.
- **`format_company_address/1` impurity** (CLAUDE #6) — still live:
  `lib/phoenix_kit_billing.ex:3414-3415` keeps the `company_info \\ nil`
  default that silently fetches via `Organization.get_company_info()`
  when called with no argument. Every current caller passes the map, so
  the impure path is dead today. Removing the default (or renaming to
  `fetch_and_format_company_address/0`) changes the public API surface;
  deferred so the signature change gets a deliberate review.
- **`permission_metadata` emoji icon (`"💰"`)** (CLAUDE #7) — minor.
  Verified still `icon: "💰"` (`lib/phoenix_kit_billing.ex:132`). The
  admin Modules card renders it as text and it displays fine in the C0
  baseline. Swapping back to a hero class (`"hero-banknotes"`, which the
  admin *tabs* already use) is a cosmetic/consistency call for the boss;
  deferred rather than changed unilaterally.
- **`city_postal` redundant `String.trim()`** (CLAUDE nit) — harmless
  defensive call; left as-is.
- **Compat module is 160+ lines of pure delegates / no removal ticket**
  (PINCER #4, MISTRAL) — the boilerplate is the intended transition
  shim; its removal condition is documented in `mix.exs` (see above).
  No code change warranted.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_billing.ex` | Added public `get_company_info/0` (extracted from the 4 print views) |
| `lib/phoenix_kit_billing/web/invoice_print.ex` | Use `Billing.get_company_info()` |
| `lib/phoenix_kit_billing/web/receipt_print.ex` | Use `Billing.get_company_info()` |
| `lib/phoenix_kit_billing/web/credit_note_print.ex` | Use `Billing.get_company_info()` |
| `lib/phoenix_kit_billing/web/payment_confirmation_print.ex` | Use `Billing.get_company_info()` |
| `mix.exs` | Expanded `ignore_module_conflict` comment with removal condition |

## Verification

`mix precommit` green (compile / format / credo --strict / dialyzer 0
errors). `mix test` — 177 tests, 0 failures, 3 skipped (the 3 skips are
the core `subscription_type_uuid` column gap documented in the module
`AGENTS.md`).

## Open

None. (Deferred items above are surfaced for Max as candidates for a
focused follow-up PR, not parked work.)
