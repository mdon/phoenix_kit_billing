defmodule PhoenixKitBilling.Web.SubscriptionTypeForm do
  @moduledoc """
  Subscription type form LiveView for creating and editing subscription types.
  """

  use Phoenix.LiveView
  use Gettext, backend: PhoenixKitBilling.Gettext
  import PhoenixKitWeb.Components.Core.AdminPageHeader
  alias PhoenixKit.Utils.Routes
  import PhoenixKitWeb.Components.Core.Icon
  import PhoenixKitBilling.Web.Components.CurrencyDisplay

  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitBilling, as: Billing
  alias PhoenixKitBilling.SubscriptionType

  @impl true
  def mount(params, _session, socket) do
    if Billing.enabled?() do
      project_title = Settings.get_project_title()
      default_currency = Settings.get_setting("billing_default_currency", "EUR")

      {type, title, mode} =
        case params do
          %{"id" => id} ->
            case Billing.get_subscription_type(id) do
              {:ok, type} -> {type, gettext("Edit Subscription Type"), :edit}
              {:error, _} -> {nil, gettext("Subscription Type Not Found"), :not_found}
            end

          _ ->
            {%SubscriptionType{
               currency: default_currency,
               interval: "month",
               interval_count: 1,
               active: true
             }, gettext("Create Subscription Type"), :new}
        end

      if type do
        changeset = SubscriptionType.changeset(type, %{})

        socket =
          socket
          |> assign(:page_title, title)
          |> assign(:project_title, project_title)
          |> assign(:mode, mode)
          |> assign(:subscription_type, type)
          |> assign(:changeset, changeset)
          |> assign(:features_input, format_features(type.features))
          |> assign(:form, to_form(changeset))

        {:ok, socket}
      else
        {:ok,
         socket
         |> put_flash(:error, gettext("Subscription type not found"))
         |> push_navigate(to: Routes.path("/admin/billing/subscription-types"))}
      end
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

  @impl true
  def handle_event("validate", %{"subscription_type" => params}, socket) do
    params = process_params(params, socket.assigns.features_input)

    changeset =
      socket.assigns.subscription_type
      |> SubscriptionType.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("update_features", %{"features" => features}, socket) do
    {:noreply, assign(socket, :features_input, features)}
  end

  @impl true
  def handle_event("save", %{"subscription_type" => params}, socket) do
    params = process_params(params, socket.assigns.features_input)

    result =
      case socket.assigns.mode do
        :new -> Billing.create_subscription_type(params)
        :edit -> Billing.update_subscription_type(socket.assigns.subscription_type, params)
      end

    case result do
      {:ok, _type} ->
        {:noreply,
         socket
         |> put_flash(:info, type_saved_message(socket.assigns.mode))
         |> push_navigate(to: Routes.path("/admin/billing/subscription-types"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Failed to save subscription type: %{reason}", reason: inspect(reason)))}
    end
  end

  defp process_params(params, features_input) do
    # Parse features from textarea (one per line)
    features =
      features_input
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Parse price from string to decimal
    price =
      case params["price"] do
        "" -> nil
        nil -> nil
        p when is_binary(p) -> Decimal.new(p)
        p -> p
      end

    params
    |> Map.put("features", features)
    |> Map.put("price", price)
  end

  defp format_features(nil), do: ""
  defp format_features(features) when is_list(features), do: Enum.join(features, "\n")
  defp format_features(_), do: ""

  defp type_saved_message(:new), do: gettext("Subscription type created successfully")
  defp type_saved_message(:edit), do: gettext("Subscription type updated successfully")

  @doc false
  def interval_phrase("day", 1), do: ngettext("per day", "per day", 1)
  def interval_phrase("day", n), do: ngettext("per %{count} days", "per %{count} days", n, count: n)
  def interval_phrase("week", 1), do: ngettext("per week", "per week", 1)
  def interval_phrase("week", n), do: ngettext("per %{count} weeks", "per %{count} weeks", n, count: n)
  def interval_phrase("month", 1), do: ngettext("per month", "per month", 1)
  def interval_phrase("month", n), do: ngettext("per %{count} months", "per %{count} months", n, count: n)
  def interval_phrase("year", 1), do: ngettext("per year", "per year", 1)
  def interval_phrase("year", n), do: ngettext("per %{count} years", "per %{count} years", n, count: n)
  def interval_phrase(other, n), do: "#{n} #{other}(s)"

  def error_to_string([]), do: ""

  def error_to_string(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", fn
      {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)

      msg when is_binary(msg) ->
        msg
    end)
  end
end
