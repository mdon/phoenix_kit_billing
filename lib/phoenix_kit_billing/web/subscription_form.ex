defmodule PhoenixKitBilling.Web.SubscriptionForm do
  @moduledoc """
  Subscription form LiveView for creating and editing subscriptions manually.

  Allows administrators to:
  - Search and select a user by email (create mode)
  - Choose a subscription type
  - Optionally assign a payment method
  - Configure trial period (create mode)
  - Manage subscription status: pause, resume, cancel (edit mode)
  - Extend subscription period (edit mode)
  """

  use Phoenix.LiveView
  use Gettext, backend: PhoenixKitBilling.Gettext
  import PhoenixKitWeb.Components.Core.AdminPageHeader
  import PhoenixKitWeb.Components.Core.UserInfo
  import PhoenixKitWeb.Components.Core.Icon
  import PhoenixKitBilling.Web.Components.CurrencyDisplay
  import PhoenixKitBilling.Web.Components.SubscriptionHelpers
  import PhoenixKitWeb.Components.Core.TimeDisplay

  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Auth
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitBilling, as: Billing
  alias PhoenixKitBilling.Activity

  @impl true
  def mount(_params, _session, socket) do
    if Billing.enabled?() do
      project_title = Settings.get_project_title()
      types = Billing.list_subscription_types(active_only: true)

      socket =
        socket
        |> assign(:page_title, gettext("Create Subscription"))
        |> assign(:project_title, project_title)
        |> assign(:subscription_types, types)
        |> assign(:user_search, "")
        |> assign(:user_results, [])
        |> assign(:selected_user, nil)
        |> assign(:selected_subscription_type_uuid, nil)
        |> assign(:payment_methods, [])
        |> assign(:selected_payment_method_uuid, nil)
        |> assign(:enable_trial, false)
        |> assign(:trial_days, "")
        |> assign(:error, nil)
        |> assign(:subscription, nil)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Billing module is not enabled"))
       |> push_navigate(to: Routes.path("/admin"))}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _url, %{assigns: %{live_action: :edit}} = socket) do
    case Billing.get_subscription(id, preload: [:subscription_type, :payment_method, :user]) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Subscription not found"))
         |> push_navigate(to: Routes.path("/admin/billing/subscriptions"))}

      subscription ->
        payment_methods = Billing.list_payment_methods(subscription.user_uuid, status: "active")

        {:noreply,
         socket
         |> assign(:page_title, gettext("Edit Subscription"))
         |> assign(:subscription, subscription)
         |> assign(:selected_user, subscription.user)
         |> assign(
           :selected_subscription_type_uuid,
           to_string(subscription.subscription_type_uuid)
         )
         |> assign(
           :selected_payment_method_uuid,
           if(subscription.payment_method_uuid,
             do: to_string(subscription.payment_method_uuid),
             else: nil
           )
         )
         |> assign(:payment_methods, payment_methods)}
    end
  end

  def handle_params(_params, _url, %{assigns: %{live_action: :new}} = socket) do
    {:noreply, assign(socket, :subscription, nil)}
  end

  @impl true
  def handle_event("search_user", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      results = search_users(query)
      {:noreply, assign(socket, user_search: query, user_results: results)}
    else
      {:noreply, assign(socket, user_search: query, user_results: [])}
    end
  end

  @impl true
  def handle_event("select_user", %{"id" => user_uuid}, socket) do
    case Auth.get_user(user_uuid) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("User not found"))}

      user ->
        payment_methods = Billing.list_payment_methods(user.uuid, status: "active")

        {:noreply,
         socket
         |> assign(:selected_user, user)
         |> assign(:user_search, user.email)
         |> assign(:user_results, [])
         |> assign(:payment_methods, payment_methods)
         |> assign(:selected_payment_method_uuid, nil)}
    end
  end

  @impl true
  def handle_event("clear_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_results, [])
     |> assign(:payment_methods, [])
     |> assign(:selected_payment_method_uuid, nil)}
  end

  @impl true
  def handle_event("select_subscription_type", %{"subscription_type_uuid" => type_uuid}, socket) do
    type_uuid = if type_uuid == "", do: nil, else: type_uuid

    # Get subscription type's default trial days
    trial_days =
      if type_uuid do
        case Enum.find(socket.assigns.subscription_types, &(to_string(&1.uuid) == type_uuid)) do
          %{trial_days: days} when is_integer(days) and days > 0 -> to_string(days)
          _ -> ""
        end
      else
        ""
      end

    {:noreply,
     socket
     |> assign(:selected_subscription_type_uuid, type_uuid)
     |> assign(:trial_days, trial_days)
     |> assign(:enable_trial, trial_days != "")}
  end

  @impl true
  def handle_event("select_payment_method", %{"payment_method_uuid" => pm_uuid}, socket) do
    pm_uuid = if pm_uuid == "", do: nil, else: pm_uuid
    {:noreply, assign(socket, :selected_payment_method_uuid, pm_uuid)}
  end

  @impl true
  def handle_event("toggle_trial", %{"enable" => enable}, socket) do
    enable = enable == "true"
    {:noreply, assign(socket, :enable_trial, enable)}
  end

  @impl true
  def handle_event("update_trial_days", %{"days" => days}, socket) do
    {:noreply, assign(socket, :trial_days, days)}
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  @impl true
  def handle_event("save", _params, %{assigns: %{live_action: :edit}} = socket) do
    subscription = socket.assigns.subscription
    new_type_uuid = socket.assigns.selected_subscription_type_uuid

    if to_string(subscription.subscription_type_uuid) == new_type_uuid do
      {:noreply,
       socket
       |> put_flash(:info, gettext("No changes to save"))
       |> push_navigate(to: Routes.path("/admin/billing/subscriptions/#{subscription.uuid}"))}
    else
      case Billing.change_subscription_type(subscription, new_type_uuid) do
        {:ok, updated} ->
          log_subscription(socket, "billing.subscription_type_changed", updated, %{
            "subscription_type_uuid" => updated.subscription_type_uuid
          })

          {:noreply,
           socket
           |> put_flash(:info, gettext("Subscription updated successfully"))
           |> push_navigate(to: Routes.path("/admin/billing/subscriptions/#{updated.uuid}"))}

        {:error, reason} ->
          {:noreply,
           assign(
             socket,
             :error,
             gettext("Failed to update subscription: %{reason}", reason: inspect(reason))
           )}
      end
    end
  end

  @impl true
  def handle_event("save", _params, socket) do
    %{
      selected_user: user,
      selected_subscription_type_uuid: type_uuid,
      selected_payment_method_uuid: pm_uuid,
      enable_trial: enable_trial,
      trial_days: trial_days
    } = socket.assigns

    cond do
      is_nil(user) ->
        {:noreply, assign(socket, :error, gettext("Please select a customer"))}

      is_nil(type_uuid) ->
        {:noreply, assign(socket, :error, gettext("Please select a subscription type"))}

      true ->
        attrs = %{
          subscription_type_uuid: type_uuid,
          payment_method_uuid: pm_uuid,
          trial_days:
            if(enable_trial && trial_days != "", do: String.to_integer(trial_days), else: 0)
        }

        case Billing.create_subscription(user.uuid, attrs) do
          {:ok, subscription} ->
            log_subscription(socket, "billing.subscription_created", subscription, %{
              "subscription_type_uuid" => subscription.subscription_type_uuid
            })

            {:noreply,
             socket
             |> put_flash(:info, gettext("Subscription created successfully"))
             |> push_navigate(
               to: Routes.path("/admin/billing/subscriptions/#{subscription.uuid}")
             )}

          {:error, %Ecto.Changeset{} = changeset} ->
            error_msg = format_changeset_errors(changeset)
            {:noreply, assign(socket, :error, error_msg)}

          {:error, reason} ->
            {:noreply,
             assign(
               socket,
               :error,
               gettext("Failed to create subscription: %{reason}", reason: inspect(reason))
             )}
        end
    end
  end

  @impl true
  def handle_event("pause_subscription", _params, socket) do
    case Billing.pause_subscription(socket.assigns.subscription) do
      {:ok, updated} ->
        log_subscription(socket, "billing.subscription_paused", updated)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Subscription paused"))
         |> push_navigate(
           to: Routes.path("/admin/billing/subscriptions/#{socket.assigns.subscription.uuid}")
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, gettext("Failed to pause: %{reason}", reason: inspect(reason)))}
    end
  end

  @impl true
  def handle_event("resume_subscription", _params, socket) do
    case Billing.resume_subscription(socket.assigns.subscription) do
      {:ok, updated} ->
        log_subscription(socket, "billing.subscription_resumed", updated)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Subscription resumed"))
         |> push_navigate(
           to: Routes.path("/admin/billing/subscriptions/#{socket.assigns.subscription.uuid}")
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, gettext("Failed to resume: %{reason}", reason: inspect(reason)))}
    end
  end

  @impl true
  def handle_event("cancel_subscription", _params, socket) do
    case Billing.cancel_subscription(socket.assigns.subscription) do
      {:ok, updated} ->
        log_subscription(socket, "billing.subscription_cancelled", updated, %{
          "immediately" => false
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Subscription will be cancelled at period end"))
         |> push_navigate(
           to: Routes.path("/admin/billing/subscriptions/#{socket.assigns.subscription.uuid}")
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, gettext("Failed to cancel: %{reason}", reason: inspect(reason)))}
    end
  end

  @impl true
  def handle_event("extend_subscription", _params, socket) do
    sub = socket.assigns.subscription
    new_end = DateTime.add(sub.current_period_end, 30, :day)

    case Billing.update_subscription(sub, %{current_period_end: new_end}) do
      {:ok, updated} ->
        log_subscription(socket, "billing.subscription_extended", updated)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Subscription extended by 30 days"))
         |> push_navigate(to: Routes.path("/admin/billing/subscriptions/#{sub.uuid}"))}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, gettext("Failed to extend: %{reason}", reason: inspect(reason)))}
    end
  end

  # Private helpers

  defp log_subscription(socket, action, subscription, extra \\ %{}) do
    Activity.log(action,
      actor_uuid: Activity.actor_uuid(socket),
      actor_role: Activity.actor_role(socket),
      resource_type: "subscription",
      resource_uuid: subscription.uuid,
      metadata: Map.merge(%{"status" => subscription.status}, extra)
    )
  end

  defp search_users(query) do
    # Use paginated search with small page size
    %{users: users} = Auth.list_users_paginated(search: query, page_size: 10)
    users
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  # Helper functions for template

  def format_payment_method(pm) do
    case pm.type do
      "card" ->
        brand = pm.brand || "Card"
        last4 = pm.last4 || "****"
        "#{String.capitalize(brand)} ending in #{last4}"

      type ->
        String.capitalize(type)
    end
  end
end
