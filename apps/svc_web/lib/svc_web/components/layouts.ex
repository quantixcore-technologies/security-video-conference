defmodule SvcWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SvcWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  attr :active, :string, default: nil, doc: "активный раздел: dashboard|users|meetings"
  attr :current_user, :map, default: nil
  attr :unread_count, :integer, default: 0

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen">
      <aside class="hidden lg:flex w-64 flex-col border-r border-base-300 bg-base-100">
        <.link
          navigate={~p"/admin"}
          class="px-5 py-5 flex items-center gap-3 border-b border-base-300"
        >
          <span class="grid place-items-center size-9 rounded-xl bg-primary/15 text-primary ring-1 ring-primary/20">
            <.icon name="hero-shield-check" class="size-5" />
          </span>
          <span class="leading-tight">
            <span class="block font-semibold text-sm tracking-tight">SVC</span>
            <span class="block text-[11px] text-base-content/50">Security Conference</span>
          </span>
        </.link>

        <nav class="flex-1 p-3 space-y-0.5">
          <.nav_item
            navigate={~p"/admin"}
            icon="hero-squares-2x2"
            label={gettext("Панель")}
            on={@active == "dashboard"}
          />
          <.nav_item
            navigate={~p"/admin/calendar"}
            icon="hero-calendar-days"
            label={gettext("Календарь")}
            on={@active == "calendar"}
          />
          <.nav_item
            navigate={~p"/admin/users"}
            icon="hero-users"
            label={gettext("Сотрудники")}
            on={@active == "users"}
          />
          <.nav_item
            navigate={~p"/admin/meetings"}
            icon="hero-video-camera"
            label={gettext("Встречи")}
            on={@active == "meetings"}
          />
          <.nav_item
            navigate={~p"/admin/tasks"}
            icon="hero-clipboard-document-list"
            label={gettext("Поручения")}
            on={@active == "tasks"}
          />
          <.nav_item
            :if={@current_user && @current_user.role in [:super_admin, :security_officer]}
            navigate={~p"/admin/security"}
            icon="hero-shield-exclamation"
            label={gettext("Безопасность")}
            on={@active == "security"}
          />
        </nav>

        <div class="p-3 border-t border-base-300">
          <.theme_toggle />
        </div>
      </aside>

      <div class="flex-1 flex flex-col min-w-0">
        <header class="sticky top-0 z-20 flex items-center justify-between gap-3 px-4 sm:px-8 h-14 border-b border-base-300 bg-base-100/85 backdrop-blur">
          <div class="flex items-center gap-2 lg:hidden">
            <div class="dropdown">
              <div
                tabindex="0"
                role="button"
                class="btn btn-ghost btn-sm btn-square"
                aria-label={gettext("Меню")}
              >
                <.icon name="hero-bars-3" class="size-5" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu mt-2 w-56 rounded-xl border border-base-300 bg-base-100 shadow-xl z-30 p-1.5 gap-0.5"
              >
                <li>
                  <.link
                    navigate={~p"/admin"}
                    class={[
                      "gap-2.5 rounded-lg",
                      @active == "dashboard" && "bg-primary/10 text-primary"
                    ]}
                  >
                    <.icon name="hero-squares-2x2" class="size-4" /> {gettext("Панель")}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/admin/calendar"}
                    class={[
                      "gap-2.5 rounded-lg",
                      @active == "calendar" && "bg-primary/10 text-primary"
                    ]}
                  >
                    <.icon name="hero-calendar-days" class="size-4" /> {gettext("Календарь")}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/admin/users"}
                    class={["gap-2.5 rounded-lg", @active == "users" && "bg-primary/10 text-primary"]}
                  >
                    <.icon name="hero-users" class="size-4" /> {gettext("Сотрудники")}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/admin/meetings"}
                    class={[
                      "gap-2.5 rounded-lg",
                      @active == "meetings" && "bg-primary/10 text-primary"
                    ]}
                  >
                    <.icon name="hero-video-camera" class="size-4" /> {gettext("Встречи")}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/admin/tasks"}
                    class={["gap-2.5 rounded-lg", @active == "tasks" && "bg-primary/10 text-primary"]}
                  >
                    <.icon name="hero-clipboard-document-list" class="size-4" /> {gettext("Поручения")}
                  </.link>
                </li>
              </ul>
            </div>
            <.link navigate={~p"/admin"} class="flex items-center gap-1.5">
              <.icon name="hero-shield-check" class="size-5 text-primary" />
              <span class="font-semibold text-sm">SVC</span>
            </.link>
          </div>
          <span class="hidden lg:block"></span>

          <div class="flex items-center gap-1.5">
            <.locale_switcher />

            <.link
              :if={@current_user}
              navigate={~p"/admin/notifications"}
              class="relative grid place-items-center size-9 rounded-lg hover:bg-base-200 transition"
              aria-label={gettext("Уведомления")}
            >
              <.icon name="hero-bell" class="size-5 text-base-content/70" />
              <span
                :if={@unread_count > 0}
                class="absolute top-1 right-1 min-w-4 h-4 px-1 grid place-items-center rounded-full bg-error text-error-content text-[10px] font-semibold tabular"
              >
                {@unread_count}
              </span>
            </.link>

            <div :if={@current_user} class="dropdown dropdown-end">
              <div
                tabindex="0"
                role="button"
                class="flex items-center gap-2.5 pl-1.5 pr-2.5 py-1.5 rounded-xl hover:bg-base-200 transition cursor-pointer"
              >
                <span class="grid place-items-center size-8 rounded-full bg-primary/15 text-primary text-xs font-semibold ring-1 ring-primary/15 overflow-hidden shrink-0">
                  <img
                    :if={@current_user.photo_path}
                    src={@current_user.photo_path}
                    class="w-full h-full object-cover"
                    alt=""
                  />
                  <span :if={!@current_user.photo_path}>
                    {user_initials(@current_user.full_name)}
                  </span>
                </span>
                <span class="hidden sm:block text-left leading-tight">
                  <span class="block text-sm font-medium">{@current_user.full_name}</span>
                  <span class="block text-[11px] text-base-content/50">
                    {role_short(@current_user.role)}
                  </span>
                </span>
                <.icon name="hero-chevron-down" class="size-4 text-base-content/40" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu mt-2 w-56 rounded-xl border border-base-300 bg-base-100 shadow-xl z-30 p-1.5 gap-0.5"
              >
                <li class="menu-title px-3 py-1.5 text-[11px] text-base-content/40 sm:hidden">
                  {@current_user.full_name}
                </li>
                <li>
                  <.link navigate={~p"/admin/profile"} class="gap-2.5 rounded-lg">
                    <.icon name="hero-user-circle" class="size-4" /> {gettext("Профиль")}
                  </.link>
                </li>
                <li>
                  <.link
                    href={~p"/logout"}
                    method="delete"
                    class="gap-2.5 rounded-lg text-error hover:bg-error/10"
                  >
                    <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> {gettext(
                      "Выйти"
                    )}
                  </.link>
                </li>
              </ul>
            </div>
          </div>
        </header>

        <main class="flex-1 px-5 sm:px-8 py-8">
          <div class="mx-auto max-w-5xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    <.assistant_widget />
    """
  end

  @doc """
  Встроенный помощник (S37) — плавающая панель в правом нижнем углу.

  Работает на обычном fetch к `/api/assistant/*`, а не на LiveView-событиях:
  ровно тот же контракт используют Android и Tauri, и держать для веба вторую
  реализацию значило бы чинить каждую правку дважды.

  `phx-update="ignore"` обязателен — иначе LiveView затирает переписку при
  каждом патче страницы.
  """
  def assistant_widget(assigns) do
    assigns = assign(assigns, :locale, Gettext.get_locale(SvcWeb.Gettext))

    ~H"""
    <div
      id="svc-assistant"
      phx-hook="Assistant"
      phx-update="ignore"
      data-locale={@locale}
      data-t-unsure={gettext("Aniq tushunmadim. Quyidagilardan birini nazarda tutdingizmi?")}
      data-t-nomatch={gettext("Buni tushunmadim. Mana nimalar bo'yicha yordam bera olaman:")}
      data-t-restricted={gettext("Bu amalni bajarish huquqi sizda yo'q. U quyidagi rollar uchun:")}
      data-t-error={gettext("Javob olinmadi. Internet aloqasini tekshiring.")}
      data-t-thinking={gettext("Qidirilmoqda…")}
    >
      <button
        type="button"
        data-toggle
        aria-expanded="false"
        aria-controls="svc-assistant-panel"
        class="fixed bottom-5 right-5 z-40 grid place-items-center size-14 rounded-full bg-primary text-primary-content shadow-lg ring-1 ring-primary/30 hover:brightness-110 transition"
        title={gettext("Yordamchi")}
      >
        <span data-icon-open>
          <.icon name="hero-chat-bubble-left-right" class="size-6" />
        </span>
        <span data-icon-close class="hidden">
          <.icon name="hero-x-mark" class="size-6" />
        </span>
      </button>

      <section
        id="svc-assistant-panel"
        hidden
        class="fixed bottom-24 right-5 z-40 flex flex-col w-[22rem] max-w-[calc(100vw-2.5rem)] h-[28rem] max-h-[calc(100vh-8rem)] rounded-2xl border border-base-300 bg-base-100 shadow-2xl overflow-hidden"
      >
        <header class="flex items-center gap-2 px-4 py-3 border-b border-base-300 bg-base-200/60">
          <span class="grid place-items-center size-8 rounded-lg bg-primary/15 text-primary">
            <.icon name="hero-sparkles" class="size-4" />
          </span>
          <span class="leading-tight">
            <span class="block text-sm font-semibold">{gettext("Yordamchi")}</span>
            <span class="block text-[11px] text-base-content/50">
              {gettext("Tizimdan foydalanish bo'yicha savollar")}
            </span>
          </span>
        </header>

        <div data-log class="flex-1 overflow-y-auto px-4 py-3 space-y-3 text-sm"></div>

        <form data-form class="flex items-center gap-2 p-3 border-t border-base-300">
          <input
            data-input
            type="text"
            autocomplete="off"
            placeholder={gettext("Savolingizni yozing…")}
            class="input input-bordered input-sm flex-1"
          />
          <button
            type="submit"
            class="btn btn-primary btn-sm btn-square"
            aria-label={gettext("Yuborish")}
          >
            <.icon name="hero-paper-airplane" class="size-4" />
          </button>
        </form>
      </section>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :on, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "group flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition",
        @on && "bg-primary/10 text-primary font-medium ring-1 ring-primary/15",
        !@on && "text-base-content/65 hover:text-base-content hover:bg-base-200"
      ]}
    >
      <.icon
        name={@icon}
        class={[
          "size-5",
          @on && "text-primary",
          !@on && "text-base-content/50 group-hover:text-base-content/80"
        ]}
      />
      {@label}
    </.link>
    """
  end

  @doc "Переключатель языка интерфейса (uz/ru/en) — ставит локаль в сессию через контроллер."
  def locale_switcher(assigns) do
    assigns = assign(assigns, :current, Gettext.get_locale(SvcWeb.Gettext))

    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="grid place-items-center h-9 px-2.5 rounded-lg hover:bg-base-200 transition text-xs font-semibold uppercase text-base-content/70"
        aria-label={gettext("Язык")}
      >
        {@current}
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu mt-2 w-40 rounded-xl border border-base-300 bg-base-100 shadow-xl z-30 p-1.5 gap-0.5"
      >
        <li :for={loc <- SvcWeb.Locale.supported()}>
          <.link
            href={~p"/locale/#{loc}"}
            class={["gap-2.5 rounded-lg", loc == @current && "bg-primary/10 text-primary"]}
          >
            {SvcWeb.Locale.label(loc)}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp user_initials(name),
    do: name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)

  defp role_short(:super_admin), do: gettext("Суперадмин")
  defp role_short(:admin_hr), do: gettext("Админ / HR")
  defp role_short(:manager), do: gettext("Руководитель")
  defp role_short(:employee), do: gettext("Сотрудник")
  defp role_short(:security_officer), do: gettext("Офицер безоп.")

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
