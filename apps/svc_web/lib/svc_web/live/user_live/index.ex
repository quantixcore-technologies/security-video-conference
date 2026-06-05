defmodule SvcWeb.UserLive.Index do
  @moduledoc "Список сотрудников (RBAC-scoped) + создание (E0)."
  use SvcWeb, :live_view

  alias Svc.{Accounts, Authz, Audit, Orgs}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     allow_upload(socket, :photo,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :index) do
    actor = socket.assigns.current_user

    socket
    |> assign(:page_title, "Сотрудники")
    |> assign(:can_manage, can_manage?(actor))
    |> assign(:departments, [])
    |> assign(:form, nil)
    |> load_users()
  end

  defp apply_action(socket, :new) do
    actor = socket.assigns.current_user

    if can_manage?(actor) do
      socket
      |> assign(:page_title, "Новый сотрудник")
      |> assign(:can_manage, true)
      |> assign(:departments, Orgs.list_departments(actor.org_id))
      |> assign(:form, to_form(Accounts.change_user_creation()))
      |> load_users()
    else
      socket
      |> put_flash(:error, "Недостаточно прав для создания сотрудников.")
      |> push_navigate(to: ~p"/admin/users")
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      params
      |> Accounts.change_user_creation()
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    actor = socket.assigns.current_user
    photo_path = consume_photo(socket, actor.org_id)

    params =
      params
      |> Map.put("org_id", actor.org_id)
      |> then(&if(photo_path, do: Map.put(&1, "photo_path", photo_path), else: &1))

    case Accounts.create_user(params) do
      {:ok, user} ->
        Audit.log_action(actor, :user_create, resource_type: :user, resource_id: user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Сотрудник #{user.full_name} создан.")
         |> push_navigate(to: ~p"/admin/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp load_users(socket) do
    users = socket.assigns.current_user |> Authz.scope_users() |> Svc.Repo.all()
    assign(socket, :users, users)
  end

  # Сохраняет загруженное фото в priv/static/uploads/photos, возвращает публичный путь.
  defp consume_photo(socket, org_id) do
    consume_uploaded_entries(socket, :photo, fn %{path: tmp}, entry ->
      dir = Path.join([:code.priv_dir(:svc_web), "static", "uploads", "photos"])
      File.mkdir_p!(dir)
      name = "#{org_id}_#{System.unique_integer([:positive])}#{Path.extname(entry.client_name)}"
      File.cp!(tmp, Path.join(dir, name))
      {:ok, "/uploads/photos/#{name}"}
    end)
    |> List.first()
  end

  defp can_manage?(%{role: role}), do: role in [:super_admin, :admin_hr]

  defp role_options, do: Enum.map(Accounts.User.roles(), &{role_label(&1), &1})
  defp dept_options(depts), do: Enum.map(depts, &{&1.name, &1.id})

  defp role_label(:super_admin), do: "Суперадмин"
  defp role_label(:admin_hr), do: "Админ/HR"
  defp role_label(:manager), do: "Руководитель"
  defp role_label(:employee), do: "Сотрудник"
  defp role_label(:security_officer), do: "Офицер безопасности"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="users">
      <.header>
        Сотрудники
        <:subtitle>Список ограничен вашей ролью (department-scoping, D-007)</:subtitle>
        <:actions>
          <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">← Панель</.link>
          <.link
            :if={@can_manage and @live_action == :index}
            navigate={~p"/admin/users/new"}
            class="btn btn-primary btn-sm"
          >
            + Сотрудник
          </.link>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 p-5 mt-4">
        <h3 class="font-semibold mb-3">Новый сотрудник</h3>
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-3">
          <.input field={@form[:full_name]} type="text" label="ФИО" required />
          <.input field={@form[:username]} type="text" label="Логин" required />
          <.input field={@form[:phone]} type="text" label="Телефон (Номер)" />
          <div>
            <label class="block text-sm font-medium mb-1">Фото (jpg/png, до 5 МБ)</label>
            <.live_file_input
              upload={@uploads.photo}
              class="file-input file-input-sm file-input-bordered w-full"
            />
            <div :for={entry <- @uploads.photo.entries} class="text-xs opacity-60 mt-1">
              {entry.client_name} · {entry.progress}%
            </div>
            <div :for={err <- upload_errors(@uploads.photo)} class="text-xs text-error mt-1">
              {inspect(err)}
            </div>
          </div>
          <.input
            field={@form[:password]}
            type="password"
            label="Временный пароль (мин. 12 символов)"
            required
          />
          <.input field={@form[:role]} type="select" label="Роль" options={role_options()} />
          <.input
            field={@form[:department_id]}
            type="select"
            label="Отдел"
            options={dept_options(@departments)}
            prompt="— не выбран —"
          />
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with="Создаём...">Создать</.button>
            <.link navigate={~p"/admin/users"} class="btn btn-ghost">Отмена</.link>
          </div>
        </.form>
      </div>

      <.table id="users" rows={@users}>
        <:col :let={u} label="ФИО">{u.full_name}</:col>
        <:col :let={u} label="Логин">{u.username}</:col>
        <:col :let={u} label="Роль">{role_label(u.role)}</:col>
        <:col :let={u} label="2FA">{if u.totp_enabled, do: "✓", else: "—"}</:col>
        <:col :let={u} label="Статус">{u.status}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
