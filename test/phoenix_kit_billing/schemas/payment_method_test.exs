defmodule PhoenixKitBilling.Schemas.PaymentMethodTest do
  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKitBilling.PaymentMethod
  alias PhoenixKitBilling.Test.Repo

  @valid %{
    provider: "stripe",
    provider_payment_method_id: "pm_123",
    user_uuid: Ecto.UUID.generate(),
    type: "card",
    brand: "visa",
    last4: "4242",
    exp_month: 12,
    exp_year: 2030
  }

  describe "changeset/2" do
    test "is valid with required fields" do
      assert PaymentMethod.changeset(%PaymentMethod{}, @valid).valid?
    end

    test "requires provider, provider_payment_method_id, user_uuid" do
      errors = errors_on(PaymentMethod.changeset(%PaymentMethod{}, %{}))
      assert "can't be blank" in errors.provider
      assert "can't be blank" in errors.provider_payment_method_id
      assert "can't be blank" in errors.user_uuid
    end

    test "rejects invalid type and status" do
      assert %{type: [_ | _]} =
               errors_on(PaymentMethod.changeset(%PaymentMethod{}, %{@valid | type: "crypto"}))

      assert %{status: [_ | _]} =
               errors_on(
                 PaymentMethod.changeset(%PaymentMethod{}, Map.put(@valid, :status, "zombie"))
               )
    end

    test "exp_month out of range invalid" do
      assert %{exp_month: [_ | _]} =
               errors_on(PaymentMethod.changeset(%PaymentMethod{}, %{@valid | exp_month: 13}))
    end

    test "exp_year too old invalid" do
      assert %{exp_year: [_ | _]} =
               errors_on(PaymentMethod.changeset(%PaymentMethod{}, %{@valid | exp_year: 2019}))
    end

    test "duplicate provider+pm_id returns a changeset error (constraint name matches DB index)" do
      # Regression: the unique_constraint name now matches the real DB index
      # `phoenix_kit_payment_methods_provider_id_uidx`, so a duplicate is
      # translated into a changeset error on :provider instead of raising.
      {:ok, _} = Repo.insert(PaymentMethod.changeset(%PaymentMethod{}, @valid))

      assert {:error, changeset} =
               Repo.insert(
                 PaymentMethod.changeset(%PaymentMethod{}, %{@valid | user_uuid: Ecto.UUID.generate()})
               )

      assert "has already been taken" in errors_on(changeset).provider
    end
  end

  describe "helpers" do
    test "expired?/1 compares against today" do
      refute PaymentMethod.expired?(%PaymentMethod{exp_month: 12, exp_year: 2999})
      assert PaymentMethod.expired?(%PaymentMethod{exp_month: 1, exp_year: 2000})
      refute PaymentMethod.expired?(%PaymentMethod{exp_month: nil, exp_year: nil})
    end

    test "usable?/1 active + not expired" do
      assert PaymentMethod.usable?(%PaymentMethod{
               status: "active",
               exp_month: 12,
               exp_year: 2999
             })

      refute PaymentMethod.usable?(%PaymentMethod{status: "removed"})
      refute PaymentMethod.usable?(%PaymentMethod{status: "active", exp_month: 1, exp_year: 2000})
    end

    test "display_name/1 for card and paypal" do
      assert PaymentMethod.display_name(%PaymentMethod{
               type: "card",
               brand: "visa",
               last4: "4242"
             }) ==
               "Visa **** 4242"

      assert PaymentMethod.display_name(%PaymentMethod{type: "paypal"}) == "PayPal"
    end

    test "expiration_string/1" do
      assert PaymentMethod.expiration_string(%PaymentMethod{exp_month: 3, exp_year: 2027}) ==
               "03/27"

      assert PaymentMethod.expiration_string(%PaymentMethod{exp_month: nil, exp_year: nil}) == nil
    end
  end
end
