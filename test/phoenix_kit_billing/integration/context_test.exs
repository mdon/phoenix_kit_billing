defmodule PhoenixKitBilling.Integration.ContextTest do
  @moduledoc """
  Context CRUD tests for `PhoenixKitBilling` functions exercisable
  without external payment APIs.

  `async: true` — no global settings touched here. Currency tests use
  non-seeded codes (EUR/GBP/USD are seeded by core V31, EUR is default).
  """

  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKitBilling, as: Billing
  alias PhoenixKitBilling.Currency

  # ── Currencies ───────────────────────────────────────────────────

  describe "currencies" do
    test "create_currency/1 inserts and upcases the code" do
      assert {:ok, c} = Billing.create_currency(%{code: "chf", name: "Swiss Franc", symbol: "Fr"})
      assert c.code == "CHF"
    end

    test "create_currency/1 returns error changeset for invalid attrs" do
      assert {:error, cs} = Billing.create_currency(%{code: "X", name: "", symbol: ""})
      assert %{code: [_ | _], name: [_ | _]} = errors_on(cs)
    end

    test "get_currency/1 by uuid and get_currency_by_code/1" do
      {:ok, c} = Billing.create_currency(%{code: "sek", name: "Krona", symbol: "kr"})
      assert Billing.get_currency(c.uuid).uuid == c.uuid
      assert Billing.get_currency_by_code("sek").uuid == c.uuid
      assert Billing.get_currency("not-a-uuid") == nil
    end

    test "update_currency/2 changes fields" do
      {:ok, c} = Billing.create_currency(%{code: "nok", name: "Krone", symbol: "kr"})
      assert {:ok, updated} = Billing.update_currency(c, %{name: "Norwegian Krone"})
      assert updated.name == "Norwegian Krone"
    end

    test "list_currencies/1 with enabled filter" do
      {:ok, _} =
        Billing.create_currency(%{code: "dkk", name: "DKK", symbol: "kr", enabled: false})

      enabled_codes = Billing.list_currencies(enabled: true) |> Enum.map(& &1.code)
      disabled_codes = Billing.list_currencies(enabled: false) |> Enum.map(& &1.code)
      assert "EUR" in enabled_codes
      assert "DKK" in disabled_codes
      refute "DKK" in enabled_codes
    end

    test "get_default_currency/1 returns the seeded EUR default" do
      assert %Currency{code: "EUR", is_default: true} = Billing.get_default_currency()
    end

    test "set_default_currency/1 moves the default flag" do
      {:ok, c} = Billing.create_currency(%{code: "pln", name: "Zloty", symbol: "zl"})
      assert {:ok, _} = Billing.set_default_currency(c)

      assert Billing.get_default_currency().code == "PLN"
      # old default (EUR) is no longer default
      assert Billing.get_currency_by_code("EUR").is_default == false
    end

    test "delete_currency/1 refuses the default" do
      default = Billing.get_default_currency()
      assert {:error, :is_default} = Billing.delete_currency(default)
    end

    test "delete_currency/1 deletes a non-default, unused currency" do
      {:ok, c} = Billing.create_currency(%{code: "huf", name: "Forint", symbol: "Ft"})
      assert {:ok, _} = Billing.delete_currency(c)
      assert Billing.get_currency(c.uuid) == nil
    end

    test "delete_currency/1 refuses a currency referenced by an order" do
      {:ok, c} = Billing.create_currency(%{code: "czk", name: "Koruna", symbol: "Kc"})

      {:ok, _order} =
        Billing.create_order(%{
          "user_uuid" => fixture_user().uuid,
          "currency" => "CZK",
          "total" => Decimal.new("10.00"),
          "billing_snapshot" => %{"email" => "g@example.com"}
        })

      assert {:error, :currency_in_use} = Billing.delete_currency(c)
    end
  end

  # ── Orders ───────────────────────────────────────────────────────

  describe "orders" do
    setup do
      {:ok, user: fixture_user()}
    end

    test "create_order/2 with a user struct", %{user: user} do
      assert {:ok, order} =
               Billing.create_order(user, %{
                 "total" => Decimal.new("99.00"),
                 "currency" => "EUR",
                 "billing_snapshot" => %{"email" => "g@example.com"}
               })

      assert order.user_uuid == user.uuid
      assert order.status == "draft"
    end

    test "create_order/2 defaults currency from settings when omitted", %{user: user} do
      assert {:ok, order} =
               Billing.create_order(user, %{
                 "total" => Decimal.new("5.00"),
                 "billing_snapshot" => %{"email" => "g@example.com"}
               })

      assert order.currency == "EUR"
    end

    test "create_order/1 with invalid attrs returns error changeset", %{user: user} do
      assert {:error, cs} =
               Billing.create_order(%{"user_uuid" => user.uuid, "total" => Decimal.new("-1")})

      assert %{total: [_ | _]} = errors_on(cs)
    end

    test "get_order/2 and get_order_by_number/1", %{user: user} do
      {:ok, order} = create_basic_order(user)
      assert Billing.get_order(order.uuid).uuid == order.uuid
      assert Billing.get_order_by_number(order.order_number).uuid == order.uuid
      assert Billing.get_order("not-a-uuid") == nil
    end

    test "update_order/2 only when editable", %{user: user} do
      {:ok, order} = create_basic_order(user)
      assert {:ok, updated} = Billing.update_order(order, %{"notes" => "hello"})
      assert updated.notes == "hello"

      {:ok, confirmed} = Billing.confirm_order(order)
      assert {:error, :order_not_editable} = Billing.update_order(confirmed, %{"notes" => "x"})
    end

    test "confirm_order/1 and mark_order_paid/2 follow the status workflow", %{user: user} do
      {:ok, order} = create_basic_order(user)
      assert {:ok, confirmed} = Billing.confirm_order(order)
      assert confirmed.status == "confirmed"

      assert {:ok, paid} = Billing.mark_order_paid(confirmed, payment_method: "bank")
      assert paid.status == "paid"
      assert paid.payment_method == "bank"

      # paid is not payable again
      assert {:error, :order_not_payable} = Billing.mark_order_paid(paid)
    end

    test "cancel_order/2 records reason", %{user: user} do
      {:ok, order} = create_basic_order(user)
      assert {:ok, cancelled} = Billing.cancel_order(order, "changed mind")
      assert cancelled.status == "cancelled"
      assert cancelled.internal_notes == "changed mind"
    end

    test "delete_order/1 only deletes drafts", %{user: user} do
      {:ok, order} = create_basic_order(user)
      {:ok, confirmed} = Billing.confirm_order(order)
      assert {:error, :can_only_delete_drafts} = Billing.delete_order(confirmed)

      {:ok, draft} = create_basic_order(user)
      assert {:ok, _} = Billing.delete_order(draft)
      assert Billing.get_order(draft.uuid) == nil
    end

    test "list_orders/1 and list_user_orders/2", %{user: user} do
      {:ok, order} = create_basic_order(user)
      assert Enum.any?(Billing.list_orders(), &(&1.uuid == order.uuid))
      assert Enum.any?(Billing.list_user_orders(user.uuid), &(&1.uuid == order.uuid))
    end
  end

  # ── Invoices ─────────────────────────────────────────────────────

  describe "invoices" do
    setup do
      {:ok, user: fixture_user()}
    end

    test "create_invoice/2 generates an invoice number", %{user: user} do
      assert {:ok, invoice} =
               Billing.create_invoice(user, %{total: Decimal.new("50.00"), currency: "EUR"})

      assert invoice.user_uuid == user.uuid
      assert is_binary(invoice.invoice_number)
      assert invoice.invoice_number =~ "INV"
    end

    test "create_invoice_from_order/2 copies order data", %{user: user} do
      {:ok, order} = create_basic_order(user)
      assert {:ok, invoice} = Billing.create_invoice_from_order(order)
      assert invoice.order_uuid == order.uuid
      assert invoice.total == order.total
      assert invoice.status == "draft"
    end

    test "get_invoice/2 and get_invoice_by_number/1", %{user: user} do
      {:ok, invoice} =
        Billing.create_invoice(user, %{total: Decimal.new("10.00"), currency: "EUR"})

      assert Billing.get_invoice(invoice.uuid).uuid == invoice.uuid
      assert Billing.get_invoice_by_number(invoice.invoice_number).uuid == invoice.uuid
      assert Billing.get_invoice("not-a-uuid") == nil
    end

    test "update_invoice/2 only when editable (draft)", %{user: user} do
      {:ok, invoice} =
        Billing.create_invoice(user, %{total: Decimal.new("10.00"), currency: "EUR"})

      assert {:ok, updated} = Billing.update_invoice(invoice, %{notes: "n"})
      assert updated.notes == "n"
    end
  end

  # ── Billing profiles ────────────────────────────────────────────

  describe "billing profiles" do
    test "create_billing_profile/2 makes the first profile default" do
      user = fixture_user()

      assert {:ok, profile} =
               Billing.create_billing_profile(user, %{
                 "type" => "individual",
                 "first_name" => "Jane",
                 "last_name" => "Roe",
                 "country" => "EE"
               })

      assert profile.is_default == true
    end

    test "create_billing_profile/2 returns error for invalid type" do
      user = fixture_user()

      assert {:error, cs} =
               Billing.create_billing_profile(user, %{"type" => "company"})

      assert %{company_name: [_ | _]} = errors_on(cs)
    end
  end

  # ── Subscription types & subscriptions ──────────────────────────

  describe "subscription types" do
    test "create / get / update / list" do
      assert {:ok, type} =
               Billing.create_subscription_type(%{
                 name: "Pro",
                 slug: "pro-#{uniq()}",
                 price: Decimal.new("29.99")
               })

      assert {:ok, ^type} = Billing.get_subscription_type(type.uuid)
      assert {:ok, updated} = Billing.update_subscription_type(type, %{name: "Pro Plus"})
      assert updated.name == "Pro Plus"
      assert Enum.any?(Billing.list_subscription_types(), &(&1.uuid == type.uuid))
    end

    test "get_subscription_type/1 returns error for missing" do
      assert {:error, :subscription_type_not_found} = Billing.get_subscription_type("not-a-uuid")
    end

    test "create_subscription_type/1 invalid attrs" do
      assert {:error, cs} = Billing.create_subscription_type(%{name: "", slug: "", price: nil})
      assert %{name: [_ | _], slug: [_ | _], price: [_ | _]} = errors_on(cs)
    end
  end

  describe "subscriptions" do
    # NOTE: the subscription create/update/status-transition tests that
    # persist a `Subscription` are SKIPPED here because the
    # `phoenix_kit_subscriptions` table built by core's versioned migrations
    # on this test DB is MISSING the `subscription_type_uuid` column that the
    # `PhoenixKitBilling.Subscription` schema declares. No core migration adds
    # that column via ADD COLUMN — it only exists via V65's conditional
    # RENAME of `plan_uuid` (which V33 never creates as `plan_uuid`; V33 uses
    # an integer `plan_id`). On a from-scratch `ensure_current/2` build the
    # column therefore never materializes, so every `Subscription` insert
    # raises `Postgrex.Error (undefined_column) subscription_type_uuid`.
    #
    # This is a core migration-chain gap (not a billing-module bug and not
    # fixable from test code). Once core ships the column (or the marker is
    # repaired), drop the `@tag :skip` markers below. The non-persisting
    # error paths are exercised unconditionally.

    test "create_subscription/2 with unknown type returns error (no insert)" do
      user = fixture_user()

      assert {:error, :subscription_type_not_found} =
               Billing.create_subscription(user.uuid, %{subscription_type_uuid: "not-a-uuid"})
    end

    test "get_subscription/2 returns nil for a non-uuid (no insert)" do
      assert Billing.get_subscription("not-a-uuid") == nil
    end

    @tag :skip
    test "create_subscription/2 with no trial is active (BLOCKED: missing column)" do
      user = fixture_user()

      {:ok, type} =
        Billing.create_subscription_type(%{
          name: "Pro",
          slug: "pro-#{uniq()}",
          price: Decimal.new("29.99")
        })

      assert {:ok, sub} =
               Billing.create_subscription(user.uuid, %{subscription_type_uuid: type.uuid})

      assert sub.status == "active"
    end

    @tag :skip
    test "status transitions: cancel / pause / resume (BLOCKED: missing column)" do
      user = fixture_user()

      {:ok, type} =
        Billing.create_subscription_type(%{
          name: "Pro",
          slug: "pro-#{uniq()}",
          price: Decimal.new("29.99")
        })

      {:ok, sub} = Billing.create_subscription(user.uuid, %{subscription_type_uuid: type.uuid})
      assert {:ok, paused} = Billing.pause_subscription(sub)
      assert paused.status == "paused"
      assert {:ok, resumed} = Billing.resume_subscription(paused)
      assert resumed.status == "active"
      assert {:ok, cancelled} = Billing.cancel_subscription(resumed, immediately: true)
      assert cancelled.status == "cancelled"
    end
  end

  # ── helpers ──────────────────────────────────────────────────────

  defp create_basic_order(user) do
    Billing.create_order(user, %{
      "total" => Decimal.new("99.00"),
      "currency" => "EUR",
      "billing_snapshot" => %{"email" => "g@example.com"},
      "line_items" => [%{"name" => "Item", "total" => "99.00"}]
    })
  end

  defp uniq, do: System.unique_integer([:positive])
end
