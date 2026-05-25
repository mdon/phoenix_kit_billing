defmodule PhoenixKitBilling.Web.SubscriptionTypes do
  @moduledoc """
  Subscription types list LiveView for the billing module.

  Displays all subscription types with management actions.
  """

  use Phoenix.LiveView
  use Gettext, backend: PhoenixKitBilling.Gettext
  import PhoenixKitWeb.Components.Core.AdminPageHeader
  import PhoenixKitWeb.Components.Core.Icon
  import PhoenixKitWeb.Components.Core.TableRowMenu
  import PhoenixKitBilling.Web.Components.CurrencyDisplay
  import PhoenixKitBilling.Web.Components.SubscriptionHelpers

  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitBilling, as: Billing

  @impl true
  def mount(_params, _session, socket) do
    if Billing.enabled?() do
      project_title = Settings.get_project_title()

      socket =
        socket
        |> assign(:page_title, gettext("Subscription Types"))
        |> assign(:project_title, project_title)
        |> load_subscription_types()

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Billing module is not enabled"))
       |> push_navigate(to: Routes.path("/admin"))}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp load_subscription_types(socket) do
    types = Billing.list_subscription_types(active_only: false)
    assign(socket, :subscription_types, types)
  end

  @impl true
  def handle_event("toggle_active", %{"uuid" => uuid}, socket) do
    type = Enum.find(socket.assigns.subscription_types, &(&1.uuid == uuid))

    if type do
      case Billing.update_subscription_type(type, %{active: !type.active}) do
        {:ok, _type} ->
          {:noreply,
           socket
           |> load_subscription_types()
           |> put_flash(
             :info,
             if(type.active,
               do: gettext("Subscription type deactivated"),
               else: gettext("Subscription type activated")
             )
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, gettext("Failed to update subscription type: %{reason}", reason: inspect(reason)))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Subscription type not found"))}
    end
  end

  @impl true
  def handle_event("delete_subscription_type", %{"uuid" => uuid}, socket) do
    type = Enum.find(socket.assigns.subscription_types, &(&1.uuid == uuid))

    if type do
      case Billing.delete_subscription_type(type) do
        {:ok, _type} ->
          {:noreply,
           socket
           |> load_subscription_types()
           |> put_flash(:info, gettext("Subscription type deleted"))}

        {:error, :has_subscriptions} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot delete subscription type with active subscriptions. Deactivate it instead.")
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, gettext("Failed to delete subscription type: %{reason}", reason: inspect(reason)))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Subscription type not found"))}
    end
  end
end
