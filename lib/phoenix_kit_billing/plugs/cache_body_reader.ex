defmodule PhoenixKitBilling.Plugs.CacheBodyReader do
  @moduledoc """
  Body reader for `Plug.Parsers` that stashes the raw request body in
  `conn.assigns.raw_body` so the webhook controller can verify provider
  signatures.

  Webhook signature verification (Stripe, PayPal, Razorpay) requires the
  *exact* bytes the provider signed. `Plug.Parsers` consumes the request
  body during JSON decoding, so the raw bytes are unavailable to
  downstream plugs unless we capture them here.

  ## Host application setup

  In your `Endpoint`, replace the default body reader on `Plug.Parsers`
  with this module **only for the webhook path** to avoid keeping every
  request body in memory:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, {:json, length: 10_000_000}],
        pass: ["*/*"],
        body_reader: {PhoenixKitBilling.Plugs.CacheBodyReader, :read_body, []},
        json_decoder: Phoenix.json_library()

  The reader only caches the body when the request path matches
  `/webhooks/billing/*`, so other requests behave normally.

  ## Why not a pipeline plug?

  `Plug.Parsers` runs in the Endpoint, before router pipelines. Once the
  body is parsed, the underlying socket is empty and a pipeline plug
  cannot recover the raw bytes. The body reader is the only safe seam.
  """

  @webhook_path_prefix "/webhooks/billing/"

  @doc """
  Reads the request body, caches it in `conn.assigns.raw_body` for
  webhook paths, and returns the standard `Plug.Conn.read_body/2` tuple.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, maybe_cache(conn, body)}

      {:more, body, conn} ->
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_cache(conn, body) do
    if webhook_path?(conn.request_path) do
      Plug.Conn.assign(conn, :raw_body, body)
    else
      conn
    end
  end

  defp webhook_path?(path) when is_binary(path) do
    String.contains?(path, @webhook_path_prefix)
  end
end
