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

  scope "/", SvcWeb do
    pipe_through :browser

    get "/", PageController, :home
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
