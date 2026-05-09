defmodule PhoenixKitBilling.Web.InvoicePrint do
  @moduledoc """
  Printable invoice view - displays invoice in a print-friendly format.

  This page is designed to be printed or saved as PDF directly from the browser.
  """

  use Phoenix.LiveView
  use Gettext, backend: PhoenixKitWeb.Gettext
  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitBilling, as: Billing
  alias PhoenixKitBilling.Transaction
  alias PhoenixKitWeb.Live.Settings.Organization

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if Billing.enabled?() do
      case Billing.get_invoice(id, preload: [:order, :transactions]) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Invoice not found")
           |> push_navigate(to: Routes.path("/admin/billing/invoices"))}

        invoice ->
          project_title = Settings.get_project_title()
          company_info = get_company_info()

          # Calculate refund info from transactions
          refund_info = calculate_refund_info(invoice.transactions)

          socket =
            socket
            |> assign(:page_title, "Invoice #{invoice.invoice_number}")
            |> assign(:project_title, project_title)
            |> assign(:invoice, invoice)
            |> assign(:company, company_info)
            |> assign(:refund_info, refund_info)

          {:ok, socket, layout: false}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "Billing module is not enabled")
       |> push_navigate(to: Routes.path("/admin"))}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp get_company_info do
    company = Organization.get_company_info()
    bank = Organization.get_bank_details()

    %{
      name: company["name"] || "",
      address: PhoenixKitBilling.format_company_address(company),
      vat: company["vat_number"] || "",
      bank_name: bank["bank_name"] || "",
      bank_iban: bank["iban"] || "",
      bank_swift: bank["swift"] || ""
    }
  end

  defp calculate_refund_info(transactions) when is_list(transactions) do
    refund_txns =
      transactions
      |> Enum.filter(&Transaction.refund?/1)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    if Enum.empty?(refund_txns) do
      nil
    else
      total_refunded =
        refund_txns
        |> Enum.map(& &1.amount)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        |> Decimal.abs()

      latest_refund = List.first(refund_txns)

      %{
        total: total_refunded,
        count: length(refund_txns),
        latest_date: latest_refund.inserted_at,
        transactions: refund_txns
      }
    end
  end

  defp calculate_refund_info(_), do: nil
end
