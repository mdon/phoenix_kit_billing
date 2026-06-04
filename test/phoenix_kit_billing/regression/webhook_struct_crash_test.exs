defmodule PhoenixKitBilling.Regression.WebhookStructCrashTest do
  @moduledoc """
  Regression test for the webhook struct-access crash.

  The bug: `upsert_webhook_event/1` read `event[:raw_payload]` via
  bracket access on a `%Providers.Types.WebhookEventData{}` struct.
  Structs don't implement the Access behaviour, so every webhook raised
  `UndefinedFunctionError (... does not implement the Access behaviour)`.

  The fix reads the field with `Map.get(event, :raw_payload)`.

  This test drives the real `WebhookProcessor.process/1` with a genuine
  `%WebhookEventData{}` struct and asserts it does NOT raise, returns an
  ok/handled result, and persists a `phoenix_kit_webhook_events` row with
  the raw payload extracted from the struct. We use an event type the
  processor does not specially handle (`"account.updated"`) so it
  short-circuits to `{:ok, :unhandled}` after exercising
  `upsert_webhook_event/1` — no Stripe API call is made.

  Touches no global settings, but webhook rows are global-ish DB state;
  kept `async: true` since each test runs in its own sandbox.
  """

  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKitBilling.Providers.Types.WebhookEventData
  alias PhoenixKitBilling.Test.Repo
  alias PhoenixKitBilling.WebhookEvent
  alias PhoenixKitBilling.WebhookProcessor

  test "process/1 with a WebhookEventData struct does not raise and persists the event" do
    event = %WebhookEventData{
      type: "account.updated",
      event_id: "evt_struct_#{System.unique_integer([:positive])}",
      provider: :stripe,
      data: %{some: "data"},
      raw_payload: %{"id" => "evt_raw_123", "object" => "event"}
    }

    # The pre-fix code raised here; the assertion is that it returns a
    # handled tuple rather than raising.
    result = WebhookProcessor.process(event)

    assert match?({:ok, _}, result)
    # Unknown type short-circuits to :unhandled after logging the event.
    assert result == {:ok, :unhandled}

    row = Repo.get_by(WebhookEvent, provider: "stripe", event_id: event.event_id)
    assert row, "expected a webhook_events row to be persisted"
    assert row.event_type == "account.updated"
    # raw_payload was read off the struct field (Map.get), not [] access.
    assert row.payload == %{"id" => "evt_raw_123", "object" => "event"}
    assert row.processed == true
  end

  test "process/1 tolerates a struct with the default empty raw_payload" do
    event = %WebhookEventData{
      type: "account.updated",
      event_id: "evt_empty_#{System.unique_integer([:positive])}",
      provider: :stripe
    }

    assert {:ok, :unhandled} = WebhookProcessor.process(event)

    row = Repo.get_by(WebhookEvent, provider: "stripe", event_id: event.event_id)
    assert row
    # Default struct raw_payload is %{}, stored as-is.
    assert row.payload == %{}
  end

  test "process/1 is idempotent — a duplicate delivery returns :duplicate_event" do
    # Regression for the unique_constraint name mismatch: the WebhookEvent
    # schema's constraint name now matches the DB index
    # (`:phoenix_kit_webhook_events_provider_event_uidx`), so a duplicate
    # delivery is caught as `{:error, changeset}` inside upsert_webhook_event/1
    # and surfaces as the intended `{:error, :duplicate_event}` — NOT the
    # `:processing_error` you'd get if the mismatch let Ecto raise.
    event = %WebhookEventData{
      type: "account.updated",
      event_id: "evt_dup_#{System.unique_integer([:positive])}",
      provider: :stripe,
      raw_payload: %{"id" => "evt_dup"}
    }

    assert {:ok, :unhandled} = WebhookProcessor.process(event)
    assert {:error, :duplicate_event} = WebhookProcessor.process(event)

    rows =
      Repo.all(
        from(we in WebhookEvent,
          where: we.provider == "stripe" and we.event_id == ^event.event_id
        )
      )

    # Idempotent: only one row persists across both deliveries.
    assert length(rows) == 1
  end
end
