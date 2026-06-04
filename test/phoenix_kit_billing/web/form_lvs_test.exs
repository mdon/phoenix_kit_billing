defmodule PhoenixKitBilling.Web.FormLvsTest do
  @moduledoc """
  LiveView tests for billing form pages that were migrated to the
  PhoenixKit core form components (`<.input>`/`<.select>`/`<.textarea>`).

  The key assertion here is that an invalid `validate` event renders the
  inline error inside the core component's `<.error>` — which only happens
  when the LV sets `:action` on the changeset and keeps `:form` in sync.
  This proves the wiring, not just that the template compiles.
  """

  use PhoenixKitBilling.LiveCase, async: false

  alias PhoenixKit.Settings

  setup %{conn: conn} do
    Settings.update_setting("billing_enabled", "true")
    scope = fake_scope()
    conn = put_test_scope(conn, scope)
    {:ok, conn: conn, user: scope.user}
  end

  describe "SubscriptionTypeForm validate errors" do
    test "renders inline errors for blank required fields on validate", %{conn: conn} do
      {:ok, view, html} = live(conn, "/en/admin/billing/subscription-types/new")

      # No errors on a fresh form (changeset has no :action yet).
      refute html =~ "can&#39;t be blank"

      rendered =
        view
        |> form("form", %{
          "subscription_type" => %{"name" => "", "slug" => "", "price" => ""}
        })
        |> render_change()

      # Core <.input> renders the translated changeset error inline once
      # :action is set on the changeset by the validate handler.
      assert rendered =~ "can&#39;t be blank"
    end
  end
end
