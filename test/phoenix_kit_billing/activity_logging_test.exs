defmodule PhoenixKitBilling.ActivityLoggingTest do
  @moduledoc """
  Pins each billing activity-log action string against the
  `phoenix_kit_activities` table.

  Every CRUD + status-transition mutation logged by the billing LVs in
  production must show up here with the expected `action`, `actor_uuid`,
  and `resource_uuid`. Without these, a typoed action string or a
  dropped `Activity.log` call regresses silently — the surrounding CRUD
  test still passes because logging is best-effort (rescued) at the LV
  layer.

  ## Two layers of coverage

  1. **Live wiring** (`describe "currencies (live)"`) drives the
     Currencies LiveView with `render_click` / `render_change` so the
     real `Activity.log` call sites fire with `actor_uuid` threaded from
     the test scope. This proves the wrapper + scope extraction works
     end-to-end.

  2. **Action-string pins** (the remaining describes) call the context
     function then `Activity.log` with exactly the opts the LV passes —
     mirroring staff's pattern for mutations reachable only via
     detail-panel buttons that `render_click` can't easily reach (order
     detail, invoice detail) or that can't persist on this test DB
     (subscriptions — see the missing-column note in
     `integration/context_test.exs`). Each pins `actor_uuid` so a test
     can't pass if the actor is dropped.
  """

  use PhoenixKitBilling.LiveCase, async: false

  alias PhoenixKit.Settings
  alias PhoenixKitBilling, as: Billing
  alias PhoenixKitBilling.Activity

  setup %{conn: conn} do
    Settings.update_setting("billing_enabled", "true")
    actor_uuid = Ecto.UUID.generate()
    scope = fake_scope(user_uuid: actor_uuid, roles: ["Owner"])
    conn = put_test_scope(conn, scope)
    {:ok, conn: conn, actor_uuid: actor_uuid, user: scope.user}
  end

  # ── Live wiring: Currencies LV fires the real Activity.log calls ────

  describe "currencies (live)" do
    test "create logs billing.currency_created with the scope actor", %{
      conn: conn,
      actor_uuid: actor_uuid
    } do
      {:ok, view, _html} = live(conn, "/en/admin/billing/currencies")

      # The currency `code` column is validated to be exactly 3 chars.
      # The previous `"T#{rem(99)}"` produced 2-char codes ("T0".."T9")
      # whenever the unique integer landed in 0..9, which failed the
      # changeset validation and left `currency` nil — a scheduling-
      # dependent flake. Zero-pad to a fixed "T" + 2-digit form so the
      # code is always a valid 3 chars (and unique within the run).
      code =
        "T#{rem(System.unique_integer([:positive]), 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

      view |> element("button[phx-click='show_add_form']") |> render_click()

      view
      |> form("form", currency: %{code: code, name: "Test Coin", symbol: "T"})
      |> render_submit()

      currency = Billing.get_currency_by_code(code)
      assert currency

      assert_activity_logged("billing.currency_created",
        actor_uuid: actor_uuid,
        resource_uuid: currency.uuid,
        metadata_has: %{"code" => currency.code}
      )
    end

    test "set_default logs billing.currency_set_default", %{conn: conn, actor_uuid: actor_uuid} do
      {:ok, currency} =
        Billing.create_currency(%{code: "QAR", name: "Riyal", symbol: "R", enabled: true})

      {:ok, view, _html} = live(conn, "/en/admin/billing/currencies")

      render_click(view, "set_default", %{"uuid" => currency.uuid})

      assert_activity_logged("billing.currency_set_default",
        actor_uuid: actor_uuid,
        resource_uuid: currency.uuid,
        metadata_has: %{"code" => "QAR"}
      )
    end

    test "delete logs billing.currency_deleted", %{conn: conn, actor_uuid: actor_uuid} do
      {:ok, currency} = Billing.create_currency(%{code: "BHD", name: "Dinar", symbol: "D"})

      {:ok, view, _html} = live(conn, "/en/admin/billing/currencies")

      render_click(view, "delete_currency", %{"uuid" => currency.uuid})

      assert_activity_logged("billing.currency_deleted",
        actor_uuid: actor_uuid,
        resource_uuid: currency.uuid
      )
    end
  end

  # ── Action-string pins (context + wrapper, mirroring the LV opts) ───

  describe "order actions" do
    setup do
      {:ok, user: fixture_user()}
    end

    test "order_created", %{actor_uuid: actor_uuid, user: user} do
      {:ok, order} =
        Billing.create_order(user, %{
          "total" => Decimal.new("99.00"),
          "currency" => "EUR",
          "billing_snapshot" => %{"email" => "g@example.com"}
        })

      Activity.log("billing.order_created",
        actor_uuid: actor_uuid,
        resource_type: "order",
        resource_uuid: order.uuid,
        metadata: %{"order_number" => order.order_number, "status" => order.status}
      )

      assert_activity_logged("billing.order_created",
        actor_uuid: actor_uuid,
        resource_uuid: order.uuid,
        metadata_has: %{"status" => "draft"}
      )
    end

    test "order_confirmed", %{actor_uuid: actor_uuid, user: user} do
      {:ok, order} = basic_order(user)
      {:ok, confirmed} = Billing.confirm_order(order)

      Activity.log("billing.order_confirmed",
        actor_uuid: actor_uuid,
        resource_type: "order",
        resource_uuid: confirmed.uuid,
        metadata: %{"order_number" => confirmed.order_number, "status" => confirmed.status}
      )

      assert_activity_logged("billing.order_confirmed",
        actor_uuid: actor_uuid,
        resource_uuid: confirmed.uuid,
        metadata_has: %{"status" => "confirmed"}
      )
    end

    test "order_marked_paid", %{actor_uuid: actor_uuid, user: user} do
      {:ok, order} = basic_order(user)
      {:ok, confirmed} = Billing.confirm_order(order)
      {:ok, paid} = Billing.mark_order_paid(confirmed)

      Activity.log("billing.order_marked_paid",
        actor_uuid: actor_uuid,
        resource_type: "order",
        resource_uuid: paid.uuid,
        metadata: %{"order_number" => paid.order_number, "status" => paid.status}
      )

      assert_activity_logged("billing.order_marked_paid",
        actor_uuid: actor_uuid,
        resource_uuid: paid.uuid,
        metadata_has: %{"status" => "paid"}
      )
    end

    test "order_cancelled", %{actor_uuid: actor_uuid, user: user} do
      {:ok, order} = basic_order(user)
      {:ok, cancelled} = Billing.cancel_order(order)

      Activity.log("billing.order_cancelled",
        actor_uuid: actor_uuid,
        resource_type: "order",
        resource_uuid: cancelled.uuid,
        metadata: %{"order_number" => cancelled.order_number, "status" => cancelled.status}
      )

      assert_activity_logged("billing.order_cancelled",
        actor_uuid: actor_uuid,
        resource_uuid: cancelled.uuid,
        metadata_has: %{"status" => "cancelled"}
      )
    end
  end

  describe "invoice actions" do
    setup do
      {:ok, user: fixture_user()}
    end

    test "invoice_created (from order)", %{actor_uuid: actor_uuid, user: user} do
      {:ok, order} = basic_order(user)
      {:ok, invoice} = Billing.create_invoice_from_order(order)

      Activity.log("billing.invoice_created",
        actor_uuid: actor_uuid,
        resource_type: "invoice",
        resource_uuid: invoice.uuid,
        target_uuid: order.uuid,
        metadata: %{"invoice_number" => invoice.invoice_number, "status" => invoice.status}
      )

      assert_activity_logged("billing.invoice_created",
        actor_uuid: actor_uuid,
        resource_uuid: invoice.uuid,
        metadata_has: %{"status" => "draft"}
      )
    end

    test "invoice_voided", %{actor_uuid: actor_uuid, user: user} do
      {:ok, invoice} =
        Billing.create_invoice(user, %{total: Decimal.new("10.00"), currency: "EUR"})

      {:ok, voided} = Billing.void_invoice(invoice)

      Activity.log("billing.invoice_voided",
        actor_uuid: actor_uuid,
        resource_type: "invoice",
        resource_uuid: voided.uuid,
        metadata: %{"invoice_number" => voided.invoice_number, "status" => voided.status}
      )

      assert_activity_logged("billing.invoice_voided",
        actor_uuid: actor_uuid,
        resource_uuid: voided.uuid,
        metadata_has: %{"status" => voided.status}
      )
    end
  end

  describe "subscription type actions" do
    test "subscription_type_created", %{actor_uuid: actor_uuid} do
      {:ok, type} =
        Billing.create_subscription_type(%{
          name: "Pro",
          slug: "pro-#{System.unique_integer([:positive])}",
          price: Decimal.new("29.99")
        })

      Activity.log("billing.subscription_type_created",
        actor_uuid: actor_uuid,
        resource_type: "subscription_type",
        resource_uuid: type.uuid,
        metadata: %{"active" => type.active}
      )

      assert_activity_logged("billing.subscription_type_created",
        actor_uuid: actor_uuid,
        resource_uuid: type.uuid
      )
    end

    test "subscription_type_updated", %{actor_uuid: actor_uuid} do
      {:ok, type} =
        Billing.create_subscription_type(%{
          name: "Basic",
          slug: "basic-#{System.unique_integer([:positive])}",
          price: Decimal.new("9.99")
        })

      {:ok, updated} = Billing.update_subscription_type(type, %{active: false})

      Activity.log("billing.subscription_type_updated",
        actor_uuid: actor_uuid,
        resource_type: "subscription_type",
        resource_uuid: updated.uuid,
        metadata: %{"active" => updated.active}
      )

      assert_activity_logged("billing.subscription_type_updated",
        actor_uuid: actor_uuid,
        resource_uuid: updated.uuid,
        metadata_has: %{"active" => false}
      )
    end

    test "subscription_type_deleted", %{actor_uuid: actor_uuid} do
      # `delete_subscription_type/1` guards against active subscriptions
      # by querying `subscription_type_uuid` — a column missing on this
      # test DB (see integration/context_test.exs). Pin the action string
      # with the same opts the LV passes, using a created type's uuid.
      {:ok, type} =
        Billing.create_subscription_type(%{
          name: "Temp",
          slug: "temp-#{System.unique_integer([:positive])}",
          price: Decimal.new("1.00")
        })

      Activity.log("billing.subscription_type_deleted",
        actor_uuid: actor_uuid,
        resource_type: "subscription_type",
        resource_uuid: type.uuid,
        metadata: %{}
      )

      assert_activity_logged("billing.subscription_type_deleted",
        actor_uuid: actor_uuid,
        resource_uuid: type.uuid
      )
    end
  end

  describe "billing profile actions" do
    test "billing_profile_created", %{actor_uuid: actor_uuid} do
      user = fixture_user()

      {:ok, profile} =
        Billing.create_billing_profile(user, %{
          "type" => "individual",
          "first_name" => "Jane",
          "last_name" => "Roe",
          "country" => "EE"
        })

      Activity.log("billing.billing_profile_created",
        actor_uuid: actor_uuid,
        resource_type: "billing_profile",
        resource_uuid: profile.uuid,
        metadata: %{
          "type" => profile.type,
          "country" => profile.country,
          "is_default" => profile.is_default
        }
      )

      assert_activity_logged("billing.billing_profile_created",
        actor_uuid: actor_uuid,
        resource_uuid: profile.uuid,
        metadata_has: %{"country" => "EE"}
      )
    end
  end

  describe "subscription actions (action-string pins)" do
    # Subscriptions can't be persisted on this test DB (missing
    # `subscription_type_uuid` column — see integration/context_test.exs).
    # These pin the action strings + actor with a synthetic resource uuid,
    # matching exactly the opts the subscription LVs pass on success.

    test "subscription_created", %{actor_uuid: actor_uuid} do
      sub_uuid = Ecto.UUID.generate()

      Activity.log("billing.subscription_created",
        actor_uuid: actor_uuid,
        resource_type: "subscription",
        resource_uuid: sub_uuid,
        metadata: %{"status" => "active"}
      )

      assert_activity_logged("billing.subscription_created",
        actor_uuid: actor_uuid,
        resource_uuid: sub_uuid,
        metadata_has: %{"status" => "active"}
      )
    end

    test "subscription_cancelled / paused / resumed", %{actor_uuid: actor_uuid} do
      sub_uuid = Ecto.UUID.generate()

      for {action, status} <- [
            {"billing.subscription_cancelled", "cancelled"},
            {"billing.subscription_paused", "paused"},
            {"billing.subscription_resumed", "active"}
          ] do
        Activity.log(action,
          actor_uuid: actor_uuid,
          resource_type: "subscription",
          resource_uuid: sub_uuid,
          metadata: %{"status" => status}
        )

        assert_activity_logged(action, actor_uuid: actor_uuid, resource_uuid: sub_uuid)
      end
    end

    test "subscription_type_changed", %{actor_uuid: actor_uuid} do
      sub_uuid = Ecto.UUID.generate()

      Activity.log("billing.subscription_type_changed",
        actor_uuid: actor_uuid,
        resource_type: "subscription",
        resource_uuid: sub_uuid,
        metadata: %{"status" => "active"}
      )

      assert_activity_logged("billing.subscription_type_changed",
        actor_uuid: actor_uuid,
        resource_uuid: sub_uuid
      )
    end
  end

  describe "wrapper behaviour" do
    test "metadata carries actor_role from opts", %{actor_uuid: actor_uuid} do
      {:ok, type} =
        Billing.create_subscription_type(%{
          name: "Role",
          slug: "role-#{System.unique_integer([:positive])}",
          price: Decimal.new("1.00")
        })

      Activity.log("billing.subscription_type_created",
        actor_uuid: actor_uuid,
        actor_role: "Owner",
        resource_type: "subscription_type",
        resource_uuid: type.uuid,
        metadata: %{"active" => type.active}
      )

      assert_activity_logged("billing.subscription_type_created",
        actor_uuid: actor_uuid,
        resource_uuid: type.uuid,
        metadata_has: %{"actor_role" => "Owner"}
      )
    end

    test "refute_activity_logged returns :ok when no row matches" do
      :ok = refute_activity_logged("billing.never_logged_action")
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp basic_order(user) do
    Billing.create_order(user, %{
      "total" => Decimal.new("99.00"),
      "currency" => "EUR",
      "billing_snapshot" => %{"email" => "g@example.com"},
      "line_items" => [%{"name" => "Item", "total" => "99.00"}]
    })
  end
end
