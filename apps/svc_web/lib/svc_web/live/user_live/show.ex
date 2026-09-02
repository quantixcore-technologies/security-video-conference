defmodule SvcWeb.UserLive.Show do
  @moduledoc "Карточка сотрудника: данные + посещаемость + управление (E0, P0)."
  use SvcWeb, :live_view

  alias Svc.{Accounts, Authz, Audit, Orgs}

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    actor = socket.assigns.current_user
    user = Accounts.get_user!(actor.org_id, id)

    if user.id in Authz.visible_user_ids(actor) do
      {:noreply,
       socket
       |> assign(:user, user)
       |> assign(:can_manage, can_manage?(actor) and actor.id != user.id)
       |> apply_action(socket.assigns.live_action)}
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("Нет доступа к этому сотруднику."))
       |> push_navigate(to: ~p"/admin/users")}
    end
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, gettext("Сотрудник не найден."))
       |> push_navigate(to: ~p"/admin/users")}
  end

  defp apply_action(socket, :show) do
    socket
    |> assign(:page_title, socket.assigns.user.full_name)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :edit) do
    actor = socket.assigns.current_user

    if socket.assigns.can_manage do
      socket
      |> assign(:page_title, gettext("Редактирование"))
      |> assign(:departments, Orgs.list_departments(actor.org_id))
      |> assign(:form, to_form(Accounts.change_user(socket.assigns.user)))
    else
      socket
      |> put_flash(:error, gettext("Недостаточно прав."))
      |> push_navigate(to: ~p"/admin/users/#{socket.assigns.user.id}")
    end
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    actor = socket.assigns.current_user
    user = socket.assigns.user

    case Accounts.update_user(user, params) do
      {:ok, updated} ->
        Audit.log_action(actor, :user_update, resource_type: :user, resource_id: updated.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Данные сотрудника обновлены."))
         |> push_navigate(to: ~p"/admin/users/#{updated.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_status", _params, socket) do
    actor = socket.assigns.current_user
    user = socket.assigns.user
    new_status = if user.status == :active, do: :disabled, else: :active

    {:ok, updated} = Accounts.set_status(user, new_status)

    Audit.log_action(actor, :user_set_status,
      resource_type: :user,
      resource_id: user.id,
      metadata: %{status: new_status}
    )

    msg =
      if new_status == :disabled,
        do: gettext("Сотрудник деактивирован."),
        else: gettext("Сотрудник активирован.")

    {:noreply, socket |> assign(:user, updated) |> put_flash(:info, msg)}
  end

  def handle_event("reset_password", _params, socket) do
    actor = socket.assigns.current_user
    user = socket.assigns.user
    temp = gen_password()

    case Accounts.admin_reset_password(user, temp) do
      {:ok, _} ->
        Audit.log_action(actor, :user_reset_password, resource_type: :user, resource_id: user.id)

        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("Временный пароль: %{password} — передайте сотруднику.", password: temp)
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Не удалось сбросить пароль."))}
    end
  end

  defp gen_password,
    do: :crypto.strong_rand_bytes(12) |> Base.url_encode64() |> binary_part(0, 16)

  # D-015: сотрудников заводит и роли назначает ТОЛЬКО super_admin (главный админ).
  defp can_manage?(%{role: role}), do: role == :super_admin

  defp role_options, do: Enum.map(Accounts.User.roles(), &{role_label(&1), &1})
  defp dept_options(depts), do: Enum.map(depts, &{&1.name, &1.id})

  defp role_label(:super_admin), do: gettext("Суперадмин")
  defp role_label(:admin_hr), do: gettext("Админ/HR")
  defp role_label(:manager), do: gettext("Руководитель")
  defp role_label(:employee), do: gettext("Сотрудник")
  defp role_label(:security_officer), do: gettext("Офицер безопасности")

  defp initials(name),
    do: name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)

  defp fmt(nil), do: "—"
  defp fmt(dt), do: Calendar.strftime(dt, "%d.%m.%Y %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active="users"
      current_user={@current_user}
      unread_count={@unread_count}
    >
      <.link
        navigate={~p"/admin/users"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/55 hover:text-base-content transition mb-5"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Все сотрудники")}
      </.link>

      <div class="rounded-xl border border-base-300 bg-base-100/50 p-6 flex items-center gap-5 mb-5">
        <span class="grid place-items-center size-20 rounded-full bg-primary/15 text-primary text-2xl font-semibold ring-1 ring-primary/15 overflow-hidden shrink-0">
          <img
            :if={@user.photo_path}
            src={@user.photo_path}
            class="w-full h-full object-cover"
            alt=""
          />
          <span :if={!@user.photo_path}>{initials(@user.full_name)}</span>
        </span>
        <div class="min-w-0 flex-1">
          <div class="text-lg font-semibold">{@user.full_name}</div>
          <div class="flex items-center gap-2 mt-1.5">
            <span class="px-2.5 py-0.5 rounded-full bg-primary/10 text-primary text-xs font-medium">
              {role_label(@user.role)}
            </span>
            <span class={[
              "inline-flex items-center gap-1.5 text-xs",
              @user.status == :active && "text-success",
              @user.status != :active && "text-base-content/45"
            ]}>
              <span class="size-1.5 rounded-full bg-current"></span>
              {if @user.status == :active, do: gettext("Активен"), else: gettext("Отключён")}
            </span>
          </div>
        </div>
        <div :if={@can_manage and @live_action == :show} class="flex items-center gap-2 shrink-0">
          <.link navigate={~p"/admin/users/#{@user.id}/edit"} class="btn btn-sm btn-ghost gap-1.5">
            <.icon name="hero-pencil-square" class="size-4" /> {gettext("Изменить")}
          </.link>
          <button
            phx-click="reset_password"
            data-confirm={gettext("Сбросить пароль сотрудника?")}
            class="btn btn-sm btn-ghost gap-1.5"
          >
            <.icon name="hero-key" class="size-4" /> {gettext("Сброс пароля")}
          </button>
          <button
            phx-click="toggle_status"
            data-confirm={
              if @user.status == :active,
                do: gettext("Деактивировать сотрудника?"),
                else: gettext("Активировать сотрудника?")
            }
            class={[
              "btn btn-sm gap-1.5",
              @user.status == :active && "btn-ghost text-error",
              @user.status != :active && "btn-ghost text-success"
            ]}
          >
            <.icon
              name={if @user.status == :active, do: "hero-no-symbol", else: "hero-check-circle"}
              class="size-4"
            />
            {if @user.status == :active, do: gettext("Деактивировать"), else: gettext("Активировать")}
          </button>
        </div>
      </div>

      <div :if={@live_action == :edit} class="rounded-xl border border-base-300 bg-base-100/50 p-5">
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-pencil-square" class="size-4 text-primary" /> {gettext(
            "Редактирование сотрудника"
          )}
        </h3>
        <.form for={@form} phx-submit="save" class="space-y-3">
          <.input field={@form[:full_name]} type="text" label={gettext("ФИО")} required />
          <.input field={@form[:phone]} type="text" label={gettext("Телефон")} />
          <.input field={@form[:role]} type="select" label={gettext("Роль")} options={role_options()} />
          <.input
            field={@form[:department_id]}
            type="select"
            label={gettext("Отдел")}
            options={dept_options(@departments)}
            prompt={gettext("— не выбран —")}
          />
          <.input
            field={@form[:status]}
            type="select"
            label={gettext("Статус")}
            options={[{gettext("Активен"), :active}, {gettext("Отключён"), :disabled}]}
          />
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with={gettext("Сохраняем...")}>
              {gettext("Сохранить")}
            </.button>
            <.link navigate={~p"/admin/users/#{@user.id}"} class="btn btn-ghost">
              {gettext("Отмена")}
            </.link>
          </div>
        </.form>
      </div>

      <div
        :if={@live_action == :show}
        class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden"
      >
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
          <.icon name="hero-identification" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">{gettext("Учётные данные")}</span>
        </div>
        <dl class="divide-y divide-base-300/50 text-sm">
          <.row label={gettext("Логин")}><span class="tabular">{@user.username}</span></.row>
          <.row label={gettext("Телефон")}>{@user.phone || "—"}</.row>
          <.row label={gettext("2FA")}>
            <span :if={@user.totp_enabled} class="inline-flex items-center gap-1 text-success">
              <.icon name="hero-shield-check" class="size-4" /> {gettext("включена")}
            </span>
            <span :if={!@user.totp_enabled} class="text-base-content/45">{gettext("выключена")}</span>
          </.row>
          <.row label={gettext("Последний вход")}>
            <span class="tabular text-base-content/70">{fmt(@user.last_login_at)}</span>
          </.row>
          <.row label={gettext("Создан")}>
            <span class="tabular text-base-content/70">{fmt(@user.inserted_at)}</span>
          </.row>
        </dl>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-5 py-3">
      <dt class="text-base-content/50">{@label}</dt>
      <dd class="font-medium">{render_slot(@inner_block)}</dd>
    </div>
    """
  end
end
