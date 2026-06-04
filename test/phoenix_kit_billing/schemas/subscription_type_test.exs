defmodule PhoenixKitBilling.Schemas.SubscriptionTypeTest do
  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKitBilling.SubscriptionType
  alias PhoenixKitBilling.Test.Repo

  @valid %{name: "Pro", slug: "pro", price: Decimal.new("29.99")}

  describe "changeset/2" do
    test "is valid with required fields" do
      assert SubscriptionType.changeset(%SubscriptionType{}, @valid).valid?
    end

    test "requires name, slug, price" do
      errors = errors_on(SubscriptionType.changeset(%SubscriptionType{}, %{}))
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.price
    end

    test "rejects invalid interval" do
      cs =
        SubscriptionType.changeset(%SubscriptionType{}, Map.put(@valid, :interval, "fortnight"))

      assert %{interval: [_ | _]} = errors_on(cs)
    end

    test "negative price / non-positive interval_count invalid" do
      assert %{price: [_ | _]} =
               errors_on(
                 SubscriptionType.changeset(%SubscriptionType{}, %{
                   @valid
                   | price: Decimal.new("-1")
                 })
               )

      assert %{interval_count: [_ | _]} =
               errors_on(
                 SubscriptionType.changeset(
                   %SubscriptionType{},
                   Map.put(@valid, :interval_count, 0)
                 )
               )
    end

    test "duplicate slug returns a changeset error (constraint name matches DB index)" do
      # Regression: unique_constraint(:slug) now pins the real DB index name
      # `phoenix_kit_subscription_types_slug_uidx`, so a duplicate is translated
      # into a changeset error instead of raising Ecto.ConstraintError.
      {:ok, _} = Repo.insert(SubscriptionType.changeset(%SubscriptionType{}, @valid))

      assert {:error, changeset} =
               Repo.insert(
                 SubscriptionType.changeset(%SubscriptionType{}, %{@valid | name: "Pro 2"})
               )

      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "helpers" do
    test "billing_period_days/1" do
      assert SubscriptionType.billing_period_days(%SubscriptionType{
               interval: "month",
               interval_count: 3
             }) == 90

      assert SubscriptionType.billing_period_days(%SubscriptionType{
               interval: "year",
               interval_count: 1
             }) == 365
    end

    test "interval_description/1" do
      assert SubscriptionType.interval_description(%SubscriptionType{
               interval: "month",
               interval_count: 1
             }) == "monthly"

      assert SubscriptionType.interval_description(%SubscriptionType{
               interval: "month",
               interval_count: 3
             }) ==
               "every 3 months"
    end

    test "next_billing_date/2 shifts by interval" do
      type = %SubscriptionType{interval: "month", interval_count: 1}
      assert SubscriptionType.next_billing_date(type, ~D[2024-01-15]) == ~D[2024-02-15]
    end
  end
end
