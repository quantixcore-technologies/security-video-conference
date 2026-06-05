defmodule SvcWeb.ProfileLive do
  @moduledoc "Профиль пользователя — данные, смена пароля, статус 2FA (E0)."
  use SvcWeb, :live_view

  alias Svc.{Accounts, Orgs, Audit}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       page_title: "Профиль",
       department: department_name(user),
       totp_setup: nil,
       form: to_form(Accounts.change_password(), as: :password)
     )}
  end

  @impl true
  def handle_event("setup_2fa", _params, socket) do
    {user, secret, uri} = Accounts.setup_totp(socket.assigns.current_user)
    qr = uri |> EQRCode.encode() |> EQRCode.svg(width: 200)

    {:noreply,
     socket
     |> assign(:current_user, user)
     |> assign(:totp_setup, %{secret: Base.encode32(secret, padding: false), uri: uri, qr: qr})}
  end

  def handle_event("confirm_2fa", %{"totp" => %{"code" => code}}, socket) do
    user = socket.assigns.current_user

    case Accounts.confirm_totp(user, String.trim(code)) do
      {:ok, updated} ->
        Audit.log_action(user, :totp_enabled, resource_type: :user, resource_id: user.id)

        {:noreply,
         socket
         |> assign(:current_user, updated)
         |> assign(:totp_setup, nil)
         |> put_flash(:info, "Двухфакторная аутентификация включена.")}

      {:error, :invalid_code} ->
        {:noreply, put_flash(socket, :error, "Неверный код. Попробуйте ещё раз.")}
    end
  end

  def handle_event("cancel_2fa", _params, socket), do: {:noreply, assign(socket, :totp_setup, nil)}

  def handle_event("disable_2fa", _params, socket) do
    user = socket.assigns.current_user
    {:ok, updated} = Accounts.disable_totp(user)
    Audit.log_action(user, :totp_disabled, resource_type: :user, resource_id: user.id)

    {:noreply,
     socket
     |> assign(:current_user, updated)
     |> put_flash(:info, "Двухфакторная аутентификация отключена.")}
  end

  @impl true
  def handle_event("change_password", %{"password" => %{"current" => cur, "new" => new}}, socket) do
    user = socket.assigns.current_user

    case Accounts.update_password(user, cur, new) do
      {:ok, _user} ->
        Audit.log_action(user, :password_changed, resource_type: :user, resource_id: user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Пароль успешно изменён.")
         |> assign(form: to_form(Accounts.change_password(), as: :password))}

      {:error, :invalid_current_password} ->
        {:noreply, put_flash(socket, :error, "Текущий пароль неверен.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form: to_form(Map.put(cs, :action, :validate), as: :password))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1 class="text-2xl font-semibold tracking-tight">Профиль</h1>
      <p class="text-sm text-base-content/55 mt-1 mb-6">Ваши данные и безопасность аккаунта</p>

      <div class="rounded-xl border border-base-300 bg-base-100/50 p-6 flex items-center gap-5 mb-5">
        <span class="grid place-items-center size-20 rounded-full bg-primary/15 text-primary text-2xl font-semibold ring-1 ring-primary/15 overflow-hidden shrink-0">
          <img :if={@current_user.photo_path} src={@current_user.photo_path} class="w-full h-full object-cover" alt="" />
          <span :if={!@current_user.photo_path}>{initials(@current_user.full_name)}</span>
        </span>
        <div class="min-w-0">
          <div class="text-lg font-semibold">{@current_user.full_name}</div>
          <div class="flex items-center gap-2 mt-1.5">
            <span class="px-2.5 py-0.5 rounded-full bg-primary/10 text-primary text-xs font-medium">
              {role_label(@current_user.role)}
            </span>
            <span :if={@department} class="inline-flex items-center gap-1 text-sm text-base-content/55">
              <.icon name="hero-building-office-2" class="size-3.5" /> {@department}
            </span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
        <div class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
          <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
            <.icon name="hero-identification" class="size-4 text-base-content/45" />
            <span class="text-sm font-medium">Учётные данные</span>
          </div>
          <dl class="divide-y divide-base-300/50 text-sm">
            <.row label="Логин"><span class="tabular">{@current_user.username}</span></.row>
            <.row label="Телефон">{@current_user.phone || "—"}</.row>
            <.row label="Статус">
              <span class={["inline-flex items-center gap-1.5", @current_user.status == :active && "text-success"]}>
                <span class="size-1.5 rounded-full bg-current"></span>
                {if @current_user.status == :active, do: "Активен", else: "Отключён"}
              </span>
            </.row>
            <.row label="Последний вход">
              <span class="tabular text-base-content/70">
                {if @current_user.last_login_at, do: Calendar.strftime(@current_user.last_login_at, "%d.%m.%Y %H:%M"), else: "—"}
              </span>
            </.row>
          </dl>
        </div>

        <div class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
          <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
            <.icon name="hero-lock-closed" class="size-4 text-base-content/45" />
            <span class="text-sm font-medium">Безопасность</span>
          </div>
          <div class="p-5 space-y-5">
            <div>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2 text-sm">
                  <.icon
                    name={if @current_user.totp_enabled, do: "hero-shield-check", else: "hero-shield-exclamation"}
                    class={["size-5", @current_user.totp_enabled && "text-success", !@current_user.totp_enabled && "text-warning"]}
                  />
                  Двухфакторная аутентификация
                </div>
                <span class={[
                  "px-2.5 py-0.5 rounded-full text-xs font-medium",
                  @current_user.totp_enabled && "bg-success/10 text-success",
                  !@current_user.totp_enabled && "bg-warning/10 text-warning"
                ]}>
                  {if @current_user.totp_enabled, do: "Включена", else: "Выключена"}
                </span>
              </div>

              <div :if={@current_user.totp_enabled and is_nil(@totp_setup)} class="mt-3">
                <button phx-click="disable_2fa" data-confirm="Отключить двухфакторную аутентификацию?" class="btn btn-ghost btn-sm text-error gap-1.5">
                  <.icon name="hero-shield-exclamation" class="size-4" /> Отключить
                </button>
              </div>

              <div :if={!@current_user.totp_enabled and is_nil(@totp_setup)} class="mt-3">
                <button phx-click="setup_2fa" class="btn btn-primary btn-sm gap-1.5">
                  <.icon name="hero-qr-code" class="size-4" /> Включить 2FA
                </button>
              </div>

              <div :if={@totp_setup} class="mt-4 rounded-lg border border-base-300 bg-base-200/30 p-4 space-y-3">
                <p class="text-xs text-base-content/60">
                  Отсканируйте QR в приложении-аутентификаторе или введите ключ вручную, затем подтвердите кодом:
                </p>
                <div class="flex gap-4 items-start flex-wrap">
                  <div class="bg-white rounded-lg p-2 shrink-0 [&_svg]:size-44">{Phoenix.HTML.raw(@totp_setup.qr)}</div>
                  <div class="min-w-0 flex-1 space-y-2.5">
                    <div>
                      <div class="text-[11px] text-base-content/50 mb-1">Ключ для ручного ввода:</div>
                      <code class="text-xs tabular break-all bg-base-300/40 px-2 py-1.5 rounded block">{@totp_setup.secret}</code>
                    </div>
                    <.form for={to_form(%{}, as: :totp)} phx-submit="confirm_2fa" class="flex gap-2">
                      <input
                        type="text"
                        name="totp[code]"
                        inputmode="numeric"
                        maxlength="6"
                        placeholder="000000"
                        required
                        autocomplete="one-time-code"
                        class="input input-sm input-bordered flex-1 bg-base-100 text-center tabular tracking-[0.3em]"
                      />
                      <button type="submit" class="btn btn-sm btn-primary">Подтвердить</button>
                    </.form>
                    <button phx-click="cancel_2fa" class="text-xs text-base-content/50 hover:text-base-content transition">
                      Отмена
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div class="border-t border-base-300/60 pt-4">
              <div class="text-xs font-medium text-base-content/60 mb-2.5">Сменить пароль</div>
              <.form for={@form} phx-submit="change_password" class="space-y-2.5">
                <input
                  type="password"
                  name="password[current]"
                  placeholder="Текущий пароль"
                  required
                  autocomplete="current-password"
                  class="input input-sm input-bordered w-full bg-base-200/40"
                />
                <input
                  type="password"
                  name="password[new]"
                  placeholder="Новый пароль (мин. 12 символов)"
                  required
                  minlength="12"
                  autocomplete="new-password"
                  class="input input-sm input-bordered w-full bg-base-200/40"
                />
                <button type="submit" phx-disable-with="Сохраняем…" class="btn btn-primary btn-sm gap-2 w-full">
                  <.icon name="hero-key" class="size-4" /> Сменить пароль
                </button>
              </.form>
            </div>
          </div>
        </div>
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

  defp department_name(%{department_id: nil}), do: nil

  defp department_name(user) do
    Orgs.get_department!(user.org_id, user.department_id).name
  rescue
    _ -> nil
  end

  defp initials(name), do: name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)

  defp role_label(:super_admin), do: "Суперадмин"
  defp role_label(:admin_hr), do: "Админ/HR"
  defp role_label(:manager), do: "Руководитель"
  defp role_label(:employee), do: "Сотрудник"
  defp role_label(:security_officer), do: "Офицер безопасности"
end
