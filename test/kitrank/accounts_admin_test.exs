defmodule Kitrank.AccountsAdminTest do
  use Kitrank.DataCase, async: true

  import Kitrank.AccountsFixtures

  alias Kitrank.Accounts

  describe "promote_to_admin/1" do
    test "legt ein Konto an, wenn es die Adresse noch nicht gibt" do
      assert {:ok, admin} = Accounts.promote_to_admin("neu@example.com")
      assert admin.email == "neu@example.com"
      assert admin.is_admin
    end

    test "befördert ein bestehendes Konto, ohne ein zweites anzulegen" do
      user = user_fixture()

      assert {:ok, admin} = Accounts.promote_to_admin(user.email)
      assert admin.id == user.id
      assert admin.is_admin
    end
  end

  describe "revoke_admin/1" do
    test "nimmt die Rechte wieder weg" do
      admin = admin_fixture()

      assert {:ok, user} = Accounts.revoke_admin(admin.email)
      refute user.is_admin
    end

    test "meldet unbekannte Adressen" do
      assert Accounts.revoke_admin("niemand@example.com") == {:error, :not_found}
    end
  end

  test "list_admins/0 zeigt nur Admins" do
    admin = admin_fixture()
    user_fixture()

    assert Enum.map(Accounts.list_admins(), & &1.id) == [admin.id]
  end

  test "Admin wird man nicht über ein Formular" do
    user = user_fixture()

    # Kein Changeset des Accounts-Contexts castet is_admin – ein untergeschobenes
    # Feld darf nicht durchschlagen.
    {:ok, _} =
      Accounts.update_user_password(user, %{password: "neues sicheres passwort", is_admin: true})

    refute Accounts.get_user!(user.id).is_admin
  end
end
