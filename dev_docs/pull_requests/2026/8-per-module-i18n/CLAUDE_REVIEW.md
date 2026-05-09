# PR #8 (phoenix_kit_billing) — Add per-module Gettext backend for sidebar tab labels

**Author:** @timujinne (Tymofii Shapovalov) · **Branch:** `feature/per-module-i18n` → `main` · **Files:** 11 (+398 / −34) · **Merged:** 2026-05-09

## Summary

Introduces `PhoenixKitBilling.Gettext` with `en` / `ru` / `et` translation catalogues covering all 13 Tab registrations across `admin_tabs/0`, `settings_tabs/0`, and `user_dashboard_tabs/0`. Every `Tab.new!/1` call now carries `gettext_backend: PhoenixKitBilling.Gettext, gettext_domain: "default"`. Phoenix_kit core resolves the label per-request once `Tab.localized_label/1` is available (BeamLabEU/phoenix_kit#522, currently open).

Graceful degradation: against the currently published phoenix_kit (≤ 1.7.105) the `gettext_backend:` field is silently dropped and tabs render raw English; the i18n test module is auto-excluded by `test/test_helper.exs` when the API isn't loaded.

## Overall verdict

**Good as merged.** Scope is clean, the graceful-degradation strategy is pragmatic, translations are thoughtful (e.g. Estonian `Püsitellimused` to disambiguate Subscriptions from Orders), and `mix.exs :package files:` correctly includes `priv` so the `.po` files actually ship to Hex consumers.

That said, there are real follow-ups worth addressing in subsequent PRs — most importantly:

1. **`module_stats/0` and `module_info/0` strings are still raw English** (lib/phoenix_kit_billing.ex:130, :141–143).
2. **13× repeated `gettext_backend:` / `gettext_domain:` boilerplate** invites drift when new tabs are added.
3. **i18n test only asserts wiring on `admin_tabs/0`** — `settings_tabs/0` and `user_dashboard_tabs/0` aren't checked.
4. **mix.lock side-effects:** the PR rides along ~14 unrelated dep bumps including `decimal` 2.3.0 → **3.0.0** (major).
5. **Manual `default.pot` maintenance is acknowledged as fragile** but not test-guarded against drift.

## Findings

### IMPROVEMENT — HIGH

#### Half-translated module surface

`module_stats/0` (lib/phoenix_kit_billing.ex:137-145) and `module_info/0` (lib/phoenix_kit_billing.ex:118-132) return raw English labels:

```elixir
%{label: "Orders", value: ...},
%{label: "Invoices", value: ...},
%{label: "Currencies", value: ...}
```

and a description string `"Orders, invoices, billing profiles and multi-currency support"`. These strings appear on the admin Modules card alongside the now-translated tab labels — the result for `ru`/`et` users will be the sidebar in their language but the module card mixing translated tab names with English stat labels. Either:

- extend the gettext catalogue to cover them (the msgids `Orders`, `Invoices`, `Currencies` already exist in `default.pot` — just need translation at the call site), **or**
- explicitly document them as out-of-scope alongside the already-acknowledged 23 LiveView body-string files.

This is a small, mechanical follow-up — but worth doing before the next release tagged "i18n complete" so consumers don't see a half-localized surface.

#### 13× boilerplate begs a helper

Every `Tab.new!` call repeats the same two keyword pairs:

```elixir
gettext_backend: PhoenixKitBilling.Gettext,
gettext_domain: "default"
```

The risk is structural: when someone adds a 14th tab, they have to remember to thread these in or it silently renders untranslated. A 5-line `defp billing_tab!(opts)` wrapper closes the foot-gun and shaves ~26 lines:

```elixir
defp billing_tab!(opts) do
  Tab.new!(
    Keyword.merge(
      [gettext_backend: PhoenixKitBilling.Gettext, gettext_domain: "default"],
      opts
    )
  )
end
```

Caller becomes `billing_tab!(id: :admin_billing, label: "Billing", ...)`. No behaviour change; pure DRY.

#### Test only asserts `admin_tabs/0`

`test/phoenix_kit_billing/i18n_test.exs:35-43` iterates `PhoenixKitBilling.admin_tabs()` only. `settings_tabs/0` (1 tab) and `user_dashboard_tabs/0` (2 tabs) are wired up in this PR but not asserted. A new tab added to either function could ship with a missing `gettext_backend` and the test suite would stay green.

Trivial fix:

```elixir
for fun <- [:admin_tabs, :settings_tabs, :user_dashboard_tabs],
    tab <- apply(PhoenixKitBilling, fun, []) do
  assert tab.gettext_backend == BillingGettext
  assert tab.gettext_domain == "default"
end
```

### IMPROVEMENT — MEDIUM

#### Manual `.pot` maintenance is fragile and not test-guarded

The `.pot` header itself acknowledges the issue (priv/gettext/default.pot:5-10):

> Tab labels are not extracted automatically by `mix gettext.extract` (they live as plain strings in `Tab.new!(label: ...)`, not in a `dgettext` macro call), so this template is maintained manually.

Manual maintenance + 11 msgids today + 13 tabs = a near-certain regression vector when a 14th tab arrives. A drift test catches this for free:

```elixir
test "every registered tab label has a msgid in default.pot" do
  msgids = parse_pot_msgids("priv/gettext/default.pot")
  for fun <- [:admin_tabs, :settings_tabs, :user_dashboard_tabs],
      tab <- apply(PhoenixKitBilling, fun, []) do
    assert tab.label in msgids,
           "Tab #{inspect(tab.id)} label #{inspect(tab.label)} missing from default.pot"
  end
end
```

Stronger version also asserts each locale's `.po` has a non-empty `msgstr` (catches "added msgid but forgot to translate to ru/et").

#### Unrelated dep bumps in mix.lock — including `decimal` 2.x → 3.x major

The diff (`git diff f12867c~1 f12867c -- mix.lock`) shows ~14 transitive bumps that aren't required by adding `:gettext`:

| dep | from | to | notes |
|---|---|---|---|
| `decimal` | 2.3.0 | **3.0.0** | major bump; ecto/postgrex use this for numerics |
| `bandit` | 1.10.4 | 1.11.0 | minor |
| `db_connection` | 2.9.0 | 2.10.0 | minor |
| `ecto` | 3.13.5 | 3.13.6 | patch |
| `oban` | 2.21.1 | 2.22.1 | minor |
| `phoenix` | 1.8.5 | 1.8.7 | patch |
| `phoenix_live_view` | 1.1.28 | 1.1.30 | patch |
| `postgrex` | 0.22.0 | 0.22.1 | patch |
| `leaf` | 0.2.6 | 0.2.13 | jumps 7 patches |
| ... | ... | ... | + bandit/jason/igniter/hammer/mimerl/beamlab_countries/aws_regions/backblaze_regions(new) |

`decimal` 3.0.0 is a breaking release for direct Decimal API users. `phoenix_kit_billing`'s own code is mostly Ecto-mediated, so practical impact is probably low — but a gettext-only PR shouldn't carry a major bump. Future PRs should `mix deps.update gettext` (just the new dep) rather than letting `mix deps.get` refresh everything. The follow-up `af82079 lib upgrades` commit already absorbed these so it's water under the bridge for this PR — note for future hygiene.

### IMPROVEMENT — LOW

#### `gettext` becomes a runtime application

`mix.exs:35`: `extra_applications: [:logger, :gettext]`. Correct, but worth noting consumers of this Hex package now boot `:gettext` even if they don't use phoenix_kit's i18n. In practice phoenix_kit core already pulls gettext in, so this is benign — but if a future "pure billing without phoenix_kit" extraction is on the table, this is a small coupling point.

#### The 23 LiveView body-string files (acknowledged)

The PR body correctly identifies that `lib/phoenix_kit_billing/web/*` still uses `PhoenixKitWeb.Gettext` (verified — `grep -rl "PhoenixKitWeb.Gettext" lib/` returns 23 files). This is the right call to defer; the migration involves running `mix gettext.extract` against a much larger surface and producing translations for likely 100+ msgids. Track as a separate issue with explicit scope.

### NITPICK

- **CHANGELOG + version bump bundled with feature.** `mix.exs @version 0.1.5` is in the same commit as the i18n changes. Splitting "feature commit" from "release commit" makes cherry-picks cleaner if a hotfix needs to fork off pre-bump. Not a blocker.
- **Test module name `PhoenixKitBilling.I18nTest`** is fine but `PhoenixKitBilling.GettextTest` would mirror the standard naming convention (test file maps 1:1 to module-under-test). Subjective.
- **Test for `unknown locale falls back to raw msgid`** (i18n_test.exs:61-66) is testing Gettext core, not this package's logic. Harmless but doesn't really earn its place.
- **`alias PhoenixKitBilling`** at i18n_test.exs:25 — aliasing a module to its own short name is a no-op since `PhoenixKitBilling` is already the qualified name. Remove.

### STRENGTHS (worth calling out)

- **Conditional `ExUnit.start/1`** in `test/test_helper.exs:11-22` is a clever bridge for the API-not-yet-published problem. Tests auto-enable the moment `phoenix_kit` ships PR #522 — no follow-up edit needed. Logger message is informative.
- **`@moduletag :requires_phoenix_kit_i18n_api`** ties the exclusion to a meaningful tag rather than a brittle skip mechanism.
- **`mix.exs :package files:` includes `priv`** — this is the kind of thing easy to forget; verifies cleanly that `.po` files reach Hex consumers.
- **Translations are thoughtful, not just machine-translated.** Estonian `Püsitellimused` (recurring orders) for *Subscriptions* explicitly disambiguates from `Tellimused` for *Orders*; Russian `Платёжные системы` for *Payment Providers* (idiomatic) over a literal `Платёжные провайдеры`.
- **`.pot` header documents the manual-maintenance trap up front** rather than letting the next contributor discover it via failed translations.

## Recommendation

**Approved (already merged).** No regressions, well-scoped, graceful degradation works. Recommended follow-up issues, in priority order:

1. **Translate `module_stats/0` and `module_info/0`** — small, finishes the visible-surface story.
2. **Extend i18n test to all three tab functions + add `.pot` drift guard.**
3. **DRY the 13 Tab.new! calls** with a `defp billing_tab!/1` helper.
4. **Track the 23-file LiveView body-string migration** as its own issue with scope.
5. **Future hygiene:** prefer `mix deps.update <new_dep>` over `mix deps.get` to avoid hitchhiking dep bumps.
