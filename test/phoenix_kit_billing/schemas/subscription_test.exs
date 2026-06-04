defmodule PhoenixKitBilling.Schemas.SubscriptionTest do
  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKit.Utils.Date, as: UtilsDate
  alias PhoenixKitBilling.Subscription

  @now UtilsDate.utc_now()

  @valid %{
    plan_name: "Pro",
    price: Decimal.new("29.99"),
    currency: "EUR",
    user_uuid: Ecto.UUID.generate(),
    subscription_type_uuid: Ecto.UUID.generate(),
    current_period_start: @now,
    current_period_end: DateTime.add(@now, 30, :day)
  }

  describe "changeset/2" do
    test "is valid with all required fields" do
      assert Subscription.changeset(%Subscription{}, @valid).valid?
    end

    test "requires plan_name, price, user_uuid, type, period bounds" do
      errors = errors_on(Subscription.changeset(%Subscription{}, %{}))
      assert "can't be blank" in errors.plan_name
      assert "can't be blank" in errors.price
      assert "can't be blank" in errors.user_uuid
      assert "can't be blank" in errors.subscription_type_uuid
      assert "can't be blank" in errors.current_period_start
      assert "can't be blank" in errors.current_period_end
    end

    test "rejects invalid status" do
      cs = Subscription.changeset(%Subscription{}, Map.put(@valid, :status, "frozen"))
      assert %{status: [_ | _]} = errors_on(cs)
    end
  end

  describe "lifecycle changesets" do
    test "activate_changeset resets dunning state" do
      sub = %Subscription{status: "past_due", renewal_attempts: 3, grace_period_end: @now}
      new_end = DateTime.add(@now, 30, :day)
      cs = Subscription.activate_changeset(sub, new_end)
      assert get_change(cs, :status) == "active"
      assert get_change(cs, :renewal_attempts) == 0
    end

    test "past_due_changeset increments attempts" do
      sub = %Subscription{status: "active", renewal_attempts: 1}
      cs = Subscription.past_due_changeset(sub, DateTime.add(@now, 3, :day))
      assert get_change(cs, :status) == "past_due"
      assert get_change(cs, :renewal_attempts) == 2
    end

    test "cancel_changeset immediately vs at-period-end" do
      sub = %Subscription{status: "active"}
      assert get_change(Subscription.cancel_changeset(sub, true), :status) == "cancelled"
      assert get_change(Subscription.cancel_changeset(sub, false), :cancel_at_period_end) == true
    end
  end

  describe "status predicates" do
    test "active?/1 true for active, trialing, past_due" do
      for s <- ~w(active trialing past_due) do
        assert Subscription.active?(%Subscription{status: s})
      end

      refute Subscription.active?(%Subscription{status: "cancelled"})
    end

    test "renewal_due?/1 compares against period end" do
      assert Subscription.renewal_due?(%Subscription{
               current_period_end: DateTime.add(@now, -1, :day)
             })

      refute Subscription.renewal_due?(%Subscription{
               current_period_end: DateTime.add(@now, 5, :day)
             })

      refute Subscription.renewal_due?(%Subscription{current_period_end: nil})
    end

    test "days_remaining/1 clamps to 0" do
      assert Subscription.days_remaining(%Subscription{
               current_period_end: DateTime.add(@now, -5, :day)
             }) == 0

      assert Subscription.days_remaining(%Subscription{
               current_period_end: DateTime.add(@now, 10, :day)
             }) >= 9
    end
  end
end
