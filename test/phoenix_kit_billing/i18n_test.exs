defmodule PhoenixKitBilling.I18nTest do
  @moduledoc """
  Smoke test for the per-module i18n wiring.

  Confirms that:
    * Every admin tab registered by `PhoenixKitBilling.admin_tabs/0`
      carries `gettext_backend: PhoenixKitBilling.Gettext`.
    * Locale switching on the module's own backend produces translated
      labels for at least one well-known msgid (regression guard for
      the `priv/gettext/<locale>/LC_MESSAGES/default.po` shipping with
      the package).
    * Falls back to the raw msgid for an unknown locale.
  """

  use ExUnit.Case, async: false

  # Excluded by `test/test_helper.exs` when running against a `phoenix_kit`
  # release that pre-dates the `gettext_backend` API (PR BeamLabEU/phoenix_kit#522).
  # Once the consumer's `phoenix_kit` dep resolves to a release that ships
  # `Tab.localized_label/1`, the helper detects it and these tests run
  # automatically — no follow-up edit needed.
  @moduletag :requires_phoenix_kit_i18n_api

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKitBilling.Gettext, as: BillingGettext

  setup do
    original = Gettext.get_locale(BillingGettext)
    on_exit(fn -> Gettext.put_locale(BillingGettext, original) end)
    :ok
  end

  describe "tab wiring (admin_tabs/0, settings_tabs/0, user_dashboard_tabs/0)" do
    test "every registered tab carries the module's own gettext backend" do
      for fun <- [:admin_tabs, :settings_tabs, :user_dashboard_tabs],
          tab <- apply(PhoenixKitBilling, fun, []) do
        assert %{gettext_backend: PhoenixKitBilling.Gettext, gettext_domain: "default"} = tab,
               "Tab #{inspect(tab.id)} from #{fun}/0 is missing or wrong gettext wiring " <>
                 "(got backend=#{inspect(tab.gettext_backend)} " <>
                 "domain=#{inspect(tab.gettext_domain)})"
      end
    end
  end

  describe "Tab.localized_label/1 against the module's catalogue" do
    test "ru locale resolves the parent 'Billing' tab to 'Биллинг'" do
      Gettext.put_locale(BillingGettext, "ru")

      parent = Enum.find(PhoenixKitBilling.admin_tabs(), &(&1.id == :admin_billing))
      assert Tab.localized_label(parent) == "Биллинг"
    end

    test "et locale resolves the parent 'Billing' tab to 'Arveldus'" do
      Gettext.put_locale(BillingGettext, "et")

      parent = Enum.find(PhoenixKitBilling.admin_tabs(), &(&1.id == :admin_billing))
      assert Tab.localized_label(parent) == "Arveldus"
    end

    test "unknown locale falls back to the raw msgid" do
      Gettext.put_locale(BillingGettext, "zz")

      parent = Enum.find(PhoenixKitBilling.admin_tabs(), &(&1.id == :admin_billing))
      assert Tab.localized_label(parent) == parent.label
    end
  end
end
