defmodule PhoenixKitBilling.CompatDelegateTest do
  @moduledoc """
  Drift guard for the temporary `PhoenixKit.Modules.Billing.*` compat
  shims under `lib/phoenix_kit_billing/compat/`.

  These modules are thin `defdelegate` layers that keep PhoenixKit core
  working while it still references the old namespace. If a delegated
  function is renamed or removed on the target module, the delegate
  becomes a runtime landmine (a `function_exported?` would pass on the
  shim but the call would crash on dispatch). This test asserts that
  every function the compat shim exports actually exists, at the same
  arity, on the module it delegates to.
  """

  use ExUnit.Case, async: true

  # compat module => target module it delegates to
  @delegate_pairs [
    {PhoenixKit.Modules.Billing, PhoenixKitBilling},
    {PhoenixKit.Modules.Billing.BillingProfile, PhoenixKitBilling.BillingProfile},
    {PhoenixKit.Modules.Billing.IbanData, PhoenixKitBilling.IbanData},
    {PhoenixKit.Modules.Billing.Web.UserBillingProfileForm,
     PhoenixKitBilling.Web.UserBillingProfileForm},
    {PhoenixKit.Modules.Billing.Web.UserBillingProfiles,
     PhoenixKitBilling.Web.UserBillingProfiles}
  ]

  # Functions injected by `use`/macros on the compat module itself
  # (e.g. Phoenix.LiveView callbacks) that are not delegated and would
  # otherwise be reported as missing on the target. We only want to
  # check the explicitly-delegated public surface.
  @ignored_funcs [
    # Elixir/OTP module internals
    module_info: 0,
    module_info: 1,
    __info__: 1,
    # Phoenix.LiveView injects these on the LiveView compat shims;
    # the genuinely delegated callbacks (mount/render/handle_*) are
    # checked separately because they DO exist on the target.
    __live__: 0,
    __components__: 0,
    __phoenix_verify_routes__: 1
  ]

  for {compat_mod, target_mod} <- @delegate_pairs do
    test "#{inspect(compat_mod)} delegates only to functions exported by #{inspect(target_mod)}" do
      compat_mod = unquote(compat_mod)
      target_mod = unquote(target_mod)

      Code.ensure_loaded!(compat_mod)
      Code.ensure_loaded!(target_mod)

      delegated =
        compat_mod.__info__(:functions)
        |> Enum.reject(fn {name, arity} -> {name, arity} in @ignored_funcs end)

      assert delegated != [], "expected #{inspect(compat_mod)} to export delegated functions"

      missing =
        Enum.reject(delegated, fn {name, arity} ->
          function_exported?(target_mod, name, arity)
        end)

      assert missing == [],
             "#{inspect(compat_mod)} delegates to #{inspect(target_mod)} functions that no " <>
               "longer exist (delegate drift): #{inspect(missing)}"
    end
  end
end
