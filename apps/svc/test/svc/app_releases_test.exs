defmodule Svc.AppReleasesTest do
  @moduledoc """
  D-020: автоматическое объявление новой версии приложения. Тесты держат две вещи,
  которые здесь критичны: ровно одно уведомление на версию и полная безопасность
  при любом сбое сети или кривом манифесте — ни рассылки, ни отметки, ни падения.
  """
  use Svc.DataCase, async: true
  use Oban.Testing, repo: Svc.Repo

  alias Svc.{Accounts, AppReleases, Notifications, Orgs}
  alias Svc.AppReleases.{Announcement, AnnounceWorker}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-releases"})
    {:ok, employee} = mk(org, "rel_emp", :employee)
    {:ok, manager} = mk(org, "rel_mgr", :manager)
    %{employee: employee, manager: manager}
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

  defp manifest(code, opts \\ []) do
    Jason.encode!(%{
      "versionCode" => code,
      "versionName" => Keyword.get(opts, :name, "0.#{code}.0"),
      "minVersionCode" => Keyword.get(opts, :min, code - 1),
      "url" => "https://example.test/app.apk?v=#{code}",
      "ios" => %{"build" => 1, "minBuild" => 1}
    })
  end

  defp serving(body), do: fn -> {:ok, body} end

  defp update_notifications(user_id) do
    user_id |> Notifications.list_for_user() |> Enum.filter(&(&1.kind == :update))
  end

  describe "check_and_announce/1" do
    test "новая версия → ровно одно уведомление каждому активному пользователю", ctx do
      assert {:announced, 2} = AppReleases.check_and_announce(fetch: serving(manifest(10)))

      assert [n] = update_notifications(ctx.employee.id)
      assert n.title == "Ilovani yangilang"
      assert n.body =~ "0.10.0"
      assert [_] = update_notifications(ctx.manager.id)

      assert %Announcement{platform: "android", version_code: 10, notified_count: 2} =
               Repo.one!(Announcement)
    end

    test "та же версия повторно — :already_announced и ни одного дубликата", ctx do
      body = manifest(11)
      assert {:announced, _} = AppReleases.check_and_announce(fetch: serving(body))
      assert :already_announced = AppReleases.check_and_announce(fetch: serving(body))

      assert [_] = update_notifications(ctx.employee.id)
      assert Repo.aggregate(Announcement, :count) == 1
    end

    test "следующая версия объявляется отдельно", ctx do
      assert {:announced, _} = AppReleases.check_and_announce(fetch: serving(manifest(20)))
      assert {:announced, _} = AppReleases.check_and_announce(fetch: serving(manifest(21)))

      assert length(update_notifications(ctx.employee.id)) == 2
    end

    test "обязательное обновление говорит, что без него продолжить нельзя", ctx do
      AppReleases.check_and_announce(fetch: serving(manifest(12, min: 12)))

      assert [n] = update_notifications(ctx.employee.id)
      assert n.body =~ "Davom etish uchun"
    end

    test "необязательное — мягкая формулировка", ctx do
      AppReleases.check_and_announce(fetch: serving(manifest(13, min: 5)))

      assert [n] = update_notifications(ctx.employee.id)
      assert n.body =~ "Yangilash uchun"
      refute n.body =~ "Davom etish uchun"
    end

    test "отключённые пользователи уведомление не получают", ctx do
      {:ok, _} = Accounts.set_status(ctx.manager, :disabled)

      assert {:announced, 1} = AppReleases.check_and_announce(fetch: serving(manifest(14)))
      assert [_] = update_notifications(ctx.employee.id)
      assert [] = update_notifications(ctx.manager.id)
    end

    test "сетевая ошибка — {:error, _}: ни уведомлений, ни отметки", ctx do
      assert {:error, :timeout} =
               AppReleases.check_and_announce(fetch: fn -> {:error, :timeout} end)

      assert [] = update_notifications(ctx.employee.id)
      assert Repo.aggregate(Announcement, :count) == 0
    end

    test "битый манифест — {:error, _}: ничего не рассылается", ctx do
      for body <- [
            "not json",
            ~s({"versionName":"1.0"}),
            ~s({"versionCode":0}),
            ~s({"versionCode":"9"})
          ] do
        assert {:error, _} = AppReleases.check_and_announce(fetch: serving(body)),
               "manifest must be rejected: #{body}"
      end

      assert [] = update_notifications(ctx.employee.id)
      assert Repo.aggregate(Announcement, :count) == 0
    end

    # Без переменной окружения рассылка выключена: локальная разработка, CI и чужие
    # развёртывания не должны слать уведомления своим пользователям.
    test "без APP_RELEASE_MANIFEST_URL — :disabled" do
      assert :disabled = AppReleases.check_and_announce()
    end
  end

  describe "decode_manifest/1" do
    test "понимает и строку JSON, и уже разобранную карту" do
      assert {:ok, %{version_code: 9, version_name: "0.5.1", mandatory?: true}} =
               AppReleases.decode_manifest(
                 ~s({"versionCode":9,"versionName":"0.5.1","minVersionCode":9})
               )

      assert {:ok, %{version_code: 9, version_name: "9", mandatory?: false}} =
               AppReleases.decode_manifest(%{"versionCode" => 9})
    end
  end

  describe "AnnounceWorker" do
    test "без URL выполняется без ошибок и ничего не рассылает", ctx do
      assert :ok = perform_job(AnnounceWorker, %{})
      assert [] = update_notifications(ctx.employee.id)
    end

    # Страховка от случайного удаления расписания: без cron автоматика молча не работает.
    test "расписание Oban Cron указывает на AnnounceWorker" do
      plugins = Application.get_env(:svc, Oban)[:plugins] || []

      assert Enum.any?(plugins, fn
               {Oban.Plugins.Cron, opts} ->
                 Enum.any?(opts[:crontab], fn {_expr, worker} -> worker == AnnounceWorker end)

               _ ->
                 false
             end)
    end
  end
end
