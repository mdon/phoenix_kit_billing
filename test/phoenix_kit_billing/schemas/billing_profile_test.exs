defmodule PhoenixKitBilling.Schemas.BillingProfileTest do
  use PhoenixKitBilling.DataCase, async: true

  alias PhoenixKitBilling.BillingProfile

  @individual %{
    user_uuid: Ecto.UUID.generate(),
    type: "individual",
    first_name: "John",
    last_name: "Doe",
    country: "EE"
  }

  @company %{
    user_uuid: Ecto.UUID.generate(),
    type: "company",
    company_name: "Acme OÜ",
    country: "EE"
  }

  describe "changeset/2" do
    test "individual is valid and auto-sets display name" do
      cs = BillingProfile.changeset(%BillingProfile{}, @individual)
      assert cs.valid?
      assert get_change(cs, :name) == "John Doe"
    end

    test "company is valid and auto-sets display name from company_name" do
      cs = BillingProfile.changeset(%BillingProfile{}, @company)
      assert cs.valid?
      assert get_change(cs, :name) == "Acme OÜ"
    end

    test "requires user_uuid and type" do
      errors = errors_on(BillingProfile.changeset(%BillingProfile{}, %{}))
      assert "can't be blank" in errors.user_uuid
      # type has a default ("individual") so it won't be blank; the
      # individual-specific required fields fire instead.
      assert Map.has_key?(errors, :first_name)
    end

    test "individual requires first_name and last_name" do
      cs =
        BillingProfile.changeset(%BillingProfile{}, %{
          user_uuid: Ecto.UUID.generate(),
          type: "individual"
        })

      errors = errors_on(cs)
      assert "is required for individuals" in errors.first_name
      assert "is required for individuals" in errors.last_name
    end

    test "company requires company_name" do
      cs =
        BillingProfile.changeset(%BillingProfile{}, %{
          user_uuid: Ecto.UUID.generate(),
          type: "company"
        })

      assert %{company_name: ["is required for companies"]} = errors_on(cs)
    end

    test "rejects invalid type" do
      cs = BillingProfile.changeset(%BillingProfile{}, %{@individual | type: "alien"})
      assert %{type: [_ | _]} = errors_on(cs)
    end

    test "country must be 2 chars" do
      cs = BillingProfile.changeset(%BillingProfile{}, %{@individual | country: "EST"})
      assert %{country: [_ | _]} = errors_on(cs)
    end

    test "invalid email format rejected" do
      cs =
        BillingProfile.changeset(%BillingProfile{}, Map.put(@individual, :email, "not an email"))

      assert %{email: [_ | _]} = errors_on(cs)
    end

    test "EU VAT number is upcased when valid" do
      attrs = Map.put(@company, :company_vat_number, "ee123456789")
      cs = BillingProfile.changeset(%BillingProfile{}, attrs)
      assert cs.valid?
      assert get_change(cs, :company_vat_number) == "EE123456789"
    end

    test "malformed EU VAT number is rejected" do
      attrs = Map.put(@company, :company_vat_number, "!!")
      cs = BillingProfile.changeset(%BillingProfile{}, attrs)
      assert %{company_vat_number: [_ | _]} = errors_on(cs)
    end
  end

  describe "to_snapshot/1" do
    test "drops nil fields and includes a snapshot timestamp" do
      profile = %BillingProfile{
        uuid: Ecto.UUID.generate(),
        type: "individual",
        name: "John Doe",
        first_name: "John",
        last_name: "Doe",
        country: "EE"
      }

      snap = BillingProfile.to_snapshot(profile)
      assert snap.name == "John Doe"
      assert snap.country == "EE"
      assert Map.has_key?(snap, :snapshot_at)
      refute Map.has_key?(snap, :company_name)
    end
  end

  describe "display_name/1" do
    test "prefers name, falls back to type-specific" do
      assert BillingProfile.display_name(%BillingProfile{name: "Explicit"}) == "Explicit"

      assert BillingProfile.display_name(%BillingProfile{
               name: nil,
               type: "individual",
               first_name: "A",
               last_name: "B"
             }) == "A B"

      assert BillingProfile.display_name(%BillingProfile{
               name: nil,
               type: "company",
               company_name: "C OÜ"
             }) ==
               "C OÜ"
    end
  end
end
