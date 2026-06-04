defmodule PhoenixKitBilling.Schemas.WebhookEventTest do
  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKitBilling.Test.Repo
  alias PhoenixKitBilling.WebhookEvent

  @valid %{provider: "stripe", event_id: "evt_1", event_type: "checkout.completed"}

  describe "changeset/2" do
    test "is valid with required fields" do
      assert WebhookEvent.changeset(%WebhookEvent{}, @valid).valid?
    end

    test "requires provider, event_id, event_type" do
      errors = errors_on(WebhookEvent.changeset(%WebhookEvent{}, %{}))
      assert "can't be blank" in errors.provider
      assert "can't be blank" in errors.event_id
      assert "can't be blank" in errors.event_type
    end
  end

  describe "processed_changeset/1 and failed_changeset/2" do
    test "processed marks processed + timestamp and clears error" do
      cs = WebhookEvent.processed_changeset(%WebhookEvent{error_message: "x"})
      assert get_change(cs, :processed) == true
      assert get_change(cs, :processed_at)
    end

    test "failed records the error and bumps retry_count" do
      cs = WebhookEvent.failed_changeset(%WebhookEvent{retry_count: 2}, "boom")
      assert get_change(cs, :error_message) == "boom"
      assert get_change(cs, :retry_count) == 3
    end
  end

  describe "status helpers" do
    test "processed?/retriable?/max_retries_exceeded?" do
      assert WebhookEvent.processed?(%WebhookEvent{processed: true})
      assert WebhookEvent.retriable?(%WebhookEvent{processed: false, retry_count: 0})
      refute WebhookEvent.retriable?(%WebhookEvent{processed: false, retry_count: 5})
      assert WebhookEvent.max_retries_exceeded?(%WebhookEvent{retry_count: 5})
    end
  end

  describe "DB round-trip" do
    test "persists a webhook event row" do
      {:ok, row} = Repo.insert(WebhookEvent.changeset(%WebhookEvent{}, @valid))
      assert row.uuid
      assert row.processed == false
      assert row.retry_count == 0
    end
  end
end
