defmodule Mix.Tasks.PhoenixKitBilling.Install do
  @moduledoc """
  Installs PhoenixKit Billing module into parent application.

  Adds the required `@source` directive to your CSS file so Tailwind CSS
  can discover classes used by the billing module's templates.

  ## Usage

      mix phoenix_kit_billing.install

  ## What it does

  1. Finds your `assets/css/app.css` file
  2. Adds `@source "../../deps/phoenix_kit_billing";` after existing `@source` lines
  3. Prints next steps for configuration

  This task is idempotent — safe to run multiple times.
  """

  use Mix.Task

  @shortdoc "Install PhoenixKit Billing module"

  @source_directive ~s(@source "../../deps/phoenix_kit_billing";)
  @source_pattern ~r/@source\s+["'][^"']*phoenix_kit_billing["']/

  @impl Mix.Task
  def run(_argv) do
    Mix.shell().info("Installing PhoenixKit Billing...")

    css_paths = [
      "assets/css/app.css",
      "priv/static/assets/app.css",
      "assets/app.css"
    ]

    case find_app_css(css_paths) do
      {:ok, css_path} ->
        add_css_source(css_path)

      {:error, :not_found} ->
        print_manual_css_instructions()
    end

    print_next_steps()
  end

  defp find_app_css(paths) do
    case Enum.find(paths, &File.exists?/1) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  defp add_css_source(css_path) do
    content = File.read!(css_path)

    if String.match?(content, @source_pattern) do
      Mix.shell().info("  ✓ CSS source already configured in #{css_path}")
    else
      updated = insert_source_directive(content)
      File.write!(css_path, updated)
      Mix.shell().info("  ✓ Added @source directive to #{css_path}")
    end
  end

  defp insert_source_directive(content) do
    lines = String.split(content, "\n")

    last_source_index =
      lines
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find(fn {line, _index} ->
        String.match?(line, ~r/^@source\s+/)
      end)

    case last_source_index do
      {_line, index} ->
        {before, after_lines} = Enum.split(lines, index + 1)
        Enum.join(before ++ [@source_directive] ++ after_lines, "\n")

      nil ->
        import_index =
          lines
          |> Enum.with_index()
          |> Enum.find(fn {line, _} -> String.match?(line, ~r/^@import\s+/) end)

        case import_index do
          {_line, index} ->
            {before, after_lines} = Enum.split(lines, index + 1)
            Enum.join(before ++ [@source_directive] ++ after_lines, "\n")

          nil ->
            @source_directive <> "\n" <> content
        end
    end
  end

  defp print_manual_css_instructions do
    Mix.shell().info("""

      ⚠  Could not find app.css. Please manually add this line:

         #{@source_directive}

      Common locations: assets/css/app.css
    """)
  end

  defp print_next_steps do
    Mix.shell().info("""

    PhoenixKit Billing installed successfully!

    Next steps:
    1. Run `mix deps.get` if you haven't already
    2. Add Oban queues to config/config.exs:
       queues: [billing: 10]
    3. Add Oban cron job to config/config.exs:
       {"0 6 * * *", PhoenixKitBilling.Workers.SubscriptionRenewalWorker}
    4. Add PhoenixKitBilling.Supervisor to your application supervision tree
    5. Wire the webhook body reader in your Endpoint's Plug.Parsers so
       provider signatures can be verified (REQUIRED — webhooks will fail
       without this):

         plug Plug.Parsers,
           parsers: [:urlencoded, :multipart, {:json, length: 10_000_000}],
           pass: ["*/*"],
           body_reader: {PhoenixKitBilling.Plugs.CacheBodyReader, :read_body, []},
           json_decoder: Phoenix.json_library()

    6. Configure payment provider API keys in Admin → Settings → Billing → Providers
    7. Run `mix phoenix_kit.update` to apply billing migrations
    8. Enable the Billing module in Admin → Modules
    """)
  end
end
