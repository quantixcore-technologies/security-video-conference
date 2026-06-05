defmodule SvcWeb.Router do
  use SvcWeb, :router

  import SvcWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SvcWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_user
    plug :require_authenticated_api
  end

  pipeline :webhook do
    plug :accepts, ["json"]
  end

  scope "/", SvcWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  ## API для Tauri-клиента (E1) — 401 JSON при отсутствии auth
  scope "/api", SvcWeb.API do
    pipe_through :api_authenticated

    post "/meetings/:id/join", MeetingController, :join
  end

  ## LiveKit вебхуки (E1) — без session-auth, подпись проверяется в контроллере
  scope "/webhooks", SvcWeb do
    pipe_through :webhook

    post "/livekit", WebhookController, :livekit
  end

  ## Аутентификация (E0, D-006)
  scope "/", SvcWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/login/totp", SessionController, :totp_form
    post "/login/totp", SessionController, :totp_verify
  end

  scope "/", SvcWeb do
    pipe_through :browser
    delete "/logout", SessionController, :delete
  end

  ## Админка — требует аутентификации (RBAC scoping внутри LiveView)
  scope "/admin", SvcWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin, on_mount: [{SvcWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive, :index
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Index, :new
      live "/meetings", MeetingLive.Index, :index
      live "/meetings/new", MeetingLive.Index, :new
      live "/meetings/:id", MeetingLive.Show, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", SvcWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:svc_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SvcWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
