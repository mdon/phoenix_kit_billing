defmodule PhoenixKitBilling.Integration.TaxAndConfigTest do
  @moduledoc """
  Tax-helper and config tests. These read/write global billing settings
  through `PhoenixKit.Settings` (cached), so they must be `async: false`.

  Each test resets the tax settings in `setup`. `update_setting/2`
  invalidates the settings cache, so cached reads pick up new values.
  """

  use PhoenixKitBilling.DataCase, async: false

  alias PhoenixKit.Settings
  alias PhoenixKitBilling, as: Billing

  setup do
    Settings.update_setting("billing_tax_enabled", "false")
    Settings.update_setting("billing_default_tax_rate", "0")
    :ok
  end

  describe "tax_enabled?/0" do
    test "reflects the billing_tax_enabled setting" do
      refute Billing.tax_enabled?()
      Settings.update_setting("billing_tax_enabled", "true")
      assert Billing.tax_enabled?()
    end
  end

  describe "get_tax_rate/0" do
    test "returns 0 when tax disabled" do
      Settings.update_setting("billing_default_tax_rate", "20")
      assert Decimal.equal?(Billing.get_tax_rate(), Decimal.new("0"))
    end

    test "returns rate/100 as a Decimal when enabled" do
      Settings.update_setting("billing_tax_enabled", "true")
      Settings.update_setting("billing_default_tax_rate", "20")
      assert Decimal.equal?(Billing.get_tax_rate(), Decimal.new("0.20"))
    end

    test "falls back to 0 for an unparseable rate" do
      Settings.update_setting("billing_tax_enabled", "true")
      Settings.update_setting("billing_default_tax_rate", "abc")
      assert Decimal.equal?(Billing.get_tax_rate(), Decimal.new("0"))
    end
  end

  describe "get_tax_rate_percent/0" do
    test "returns 0 when disabled" do
      Settings.update_setting("billing_default_tax_rate", "20")
      assert Billing.get_tax_rate_percent() == 0
    end

    test "returns the integer percentage when enabled" do
      Settings.update_setting("billing_tax_enabled", "true")
      Settings.update_setting("billing_default_tax_rate", "20")
      assert Billing.get_tax_rate_percent() == 20
    end
  end

  describe "get_config/0" do
    test "returns the merged config map with expected keys" do
      config = Billing.get_config()
      assert Map.has_key?(config, :enabled)
      assert Map.has_key?(config, :default_currency)
      assert Map.has_key?(config, :invoice_prefix)
      assert is_integer(config.invoice_due_days)
    end
  end
end
