defmodule Svc.DocumentsTest do
  @moduledoc """
  S40 — обмен документами. Главное здесь не «файл сохранился», а границы доступа:
  чужая организация, не-получатель, отзыв и срок действия (D-005, D-016/D-021).
  """
  use Svc.DataCase, async: true

  alias Svc.{Accounts, Documents, Orgs}
  alias Svc.Documents.Storage

  @content "СЕКРЕТНО: протокол совещания №14"

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "doc-org"})
    {:ok, boss} = mk(org, "boss", :manager)
    {:ok, emp} = mk(org, "emp", :employee)
    {:ok, other_emp} = mk(org, "other", :employee)
    %{org: org, boss: boss, emp: emp, other_emp: other_emp}
  end

  defp mk(org, username, role) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: "User #{username}",
      password: "SecurePass123!",
      role: role
    })
  end

  defp upload(actor, recipients, attrs \\ %{}) do
    Documents.upload(
      actor,
      Map.merge(
        %{
          "title" => "Протокол",
          "filename" => "protokol.pdf",
          "content_type" => "application/pdf",
          "recipient_ids" => Enum.map(recipients, & &1.id)
        },
        attrs
      ),
      @content
    )
  end

  describe "upload/3" do
    test "руководитель загружает документ получателю", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp])
      assert document.owner_id == boss.id
      assert document.byte_size == byte_size(@content)
      assert document.version == 1
      assert [recipient] = document.recipients
      assert recipient.user_id == emp.id
    end

    test "рядовой сотрудник отправлять не может (D-015)", %{emp: emp, other_emp: other} do
      assert {:error, :unauthorized} = upload(emp, [other])
    end

    test "пустой файл и превышение размера отклоняются", %{boss: boss, emp: emp} do
      attrs = %{"title" => "Пустой", "filename" => "x.pdf", "recipient_ids" => [emp.id]}
      assert {:error, :empty_file} = Documents.upload(boss, attrs, "")

      big = :binary.copy("a", Documents.max_bytes() + 1)
      assert {:error, :too_large} = Documents.upload(boss, attrs, big)
    end

    test "получателем может стать только пользователь своей организации", %{boss: boss} do
      {:ok, other_org} = Orgs.create_organization(%{name: "Чужая", slug: "alien"})
      {:ok, alien} = mk(other_org, "alien", :employee)

      assert {:ok, document} = upload(boss, [alien])
      assert document.recipients == []
    end

    test "файл на диске зашифрован — открытым текстом не лежит", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp])
      raw = File.read!(Storage.path(document.storage_key))

      refute raw == @content
      refute String.contains?(raw, "СЕКРЕТНО")
      assert {:ok, @content} = Storage.get(document.storage_key)
    end
  end

  describe "видимость" do
    test "получатель видит, посторонний из той же организации — нет", ctx do
      %{boss: boss, emp: emp, other_emp: other} = ctx
      assert {:ok, document} = upload(boss, [emp])

      assert [found] = Documents.list_visible(emp)
      assert found.id == document.id
      assert {:ok, _} = Documents.fetch(emp, document.id)

      assert Documents.list_visible(other) == []
      assert {:error, :not_found} = Documents.fetch(other, document.id)
    end

    test "чужая организация не видит (D-005)", %{boss: boss, emp: emp} do
      {:ok, other_org} = Orgs.create_organization(%{name: "Чужая", slug: "alien2"})
      {:ok, alien} = mk(other_org, "alien", :manager)

      assert {:ok, document} = upload(boss, [emp])
      assert Documents.list_visible(alien) == []
      assert {:error, :not_found} = Documents.fetch(alien, document.id)
    end

    test "автор видит свой документ всегда", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp])
      assert [found] = Documents.list_visible(boss)
      assert found.id == document.id
    end
  end

  describe "download/2" do
    test "получатель скачивает, отметка об открытии ставится", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp])
      assert {:ok, _document, content} = Documents.download(emp, document.id)
      assert content == @content

      {:ok, reloaded} = Documents.fetch(boss, document.id)
      assert [recipient] = reloaded.recipients
      assert recipient.opened_at
    end

    test "посторонний скачать не может", %{boss: boss, emp: emp, other_emp: other} do
      assert {:ok, document} = upload(boss, [emp])
      assert {:error, :not_found} = Documents.download(other, document.id)
    end

    test "подменённый блоб не отдаётся (контроль целостности)", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp])
      File.write!(Storage.path(document.storage_key), Svc.Vault.encrypt!("подмена"))

      assert {:error, :corrupted} = Documents.download(emp, document.id)
    end
  end

  describe "revoke/2" do
    test "автор отзывает — получатель теряет доступ, автор сохраняет", ctx do
      %{boss: boss, emp: emp} = ctx
      assert {:ok, document} = upload(boss, [emp])
      assert {:ok, revoked} = Documents.revoke(boss, document.id)
      assert revoked.revoked_at

      assert Documents.list_visible(emp) == []
      assert {:error, :not_found} = Documents.download(emp, document.id)
      assert {:ok, _} = Documents.fetch(boss, document.id)
    end

    test "получатель отозвать не может", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp])
      assert {:error, :unauthorized} = Documents.revoke(emp, document.id)
    end

    test "super_admin организации может отозвать чужой документ", %{org: org} = ctx do
      %{boss: boss, emp: emp} = ctx
      {:ok, admin} = mk(org, "root", :super_admin)

      assert {:ok, document} = upload(boss, [emp])

      # D-022: отозвать — может (админская необходимость), прочитать — нет.
      assert {:ok, _} = Documents.revoke(admin, document.id)
      assert {:error, :not_found} = Documents.download(admin, document.id)
      assert Documents.list_visible(admin) == []
    end
  end

  describe "срок действия" do
    test "просроченный документ получателю не виден", %{boss: boss, emp: emp} do
      assert {:ok, document} = upload(boss, [emp], %{"expires_at" => in_hours(1)})

      # Двигаем срок в прошлое напрямую: changeset намеренно не принимает прошлое.
      Svc.Repo.update_all(
        from(d in Svc.Documents.Document, where: d.id == ^document.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )

      assert Documents.list_visible(emp) == []
      assert {:error, :not_found} = Documents.fetch(emp, document.id)
      assert {:ok, _} = Documents.fetch(boss, document.id)
    end

    test "срок в прошлом при загрузке отклоняется", %{boss: boss, emp: emp} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert {:error, changeset} = upload(boss, [emp], %{"expires_at" => past})
      assert "должен быть в будущем" in errors_on(changeset).expires_at
    end
  end

  describe "версии" do
    test "новая версия наследует получателей и растит номер", %{boss: boss, emp: emp} do
      assert {:ok, v1} = upload(boss, [emp])

      assert {:ok, v2} =
               Documents.new_version(
                 boss,
                 v1.id,
                 %{"filename" => "protokol-v2.pdf"},
                 "новое тело"
               )

      assert v2.version == 2
      assert v2.parent_id == v1.id
      assert [recipient] = v2.recipients
      assert recipient.user_id == emp.id

      assert {:ok, versions} = Documents.versions(boss, v1.id)
      assert Enum.map(versions, & &1.version) == [2, 1]
    end

    test "не-автор новую версию создать не может", %{boss: boss, emp: emp} do
      assert {:ok, v1} = upload(boss, [emp])
      assert {:error, :unauthorized} = Documents.new_version(emp, v1.id, %{}, "тело")
    end
  end

  defp in_hours(hours), do: DateTime.add(DateTime.utc_now(), hours * 3600, :second)
end
