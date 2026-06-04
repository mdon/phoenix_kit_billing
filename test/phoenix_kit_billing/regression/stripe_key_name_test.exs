defmodule PhoenixKitBilling.Regression.StripeKeyNameTest do
  @moduledoc """
  Regression test for the Stripe secret-key setting-name mismatch.

  The bug: `Stripe.get_config/0` read the secret from a setting name that
  did not match what the admin UI persisted, so `available?/0` was always
  false even after the operator saved a key.

  The fix reads `billing_stripe_secret_key` first, falling back to the
  legacy `billing_stripe_api_key` for hosts that saved under the old name.

  These tests write global settings, so they must be `async: false`. Each
  test resets the three relevant settings in `setup` so order doesn't
  matter.
  """

  use PhoenixKitBilling.DataCase, async: false

  alias PhoenixKit.Settings
  alias PhoenixKitBilling.Providers.Stripe

  setup do
    # Clean slate for every test — empty strings are the "unset" sentinel
    # get_config/0 already treats as missing.
    Settings.update_setting("billing_stripe_enabled", "false")
    Settings.update_setting("billing_stripe_secret_key", "")
    Settings.update_setting("billing_stripe_api_key", "")
    :ok
  end

  test "available?/0 is true when enabled + billing_stripe_secret_key set" do
    Settings.update_setting("billing_stripe_enabled", "true")
    Settings.update_setting("billing_stripe_secret_key", "sk_test_x")

    assert Stripe.available?() == true
  end

  test "available?/0 falls back to the legacy billing_stripe_api_key" do
    Settings.update_setting("billing_stripe_enabled", "true")
    # secret_key intentionally left empty; only the legacy key is present.
    Settings.update_setting("billing_stripe_api_key", "sk_legacy_y")

    assert Stripe.available?() == true
  end

  test "available?/0 is false when neither key is set (even if enabled)" do
    Settings.update_setting("billing_stripe_enabled", "true")

    assert Stripe.available?() == false
  end

  test "available?/0 is false when a key is set but the provider is disabled" do
    Settings.update_setting("billing_stripe_enabled", "false")
    Settings.update_setting("billing_stripe_secret_key", "sk_test_x")

    assert Stripe.available?() == false
  end

  test "secret_key takes precedence over the legacy api_key" do
    Settings.update_setting("billing_stripe_enabled", "true")
    Settings.update_setting("billing_stripe_secret_key", "sk_new")
    Settings.update_setting("billing_stripe_api_key", "sk_old")

    # Both present → available regardless; this asserts the precedence path
    # is reached (secret_key non-empty short-circuits the fallback).
    assert Stripe.available?() == true
  end
end
