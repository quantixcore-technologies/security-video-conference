# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :svc,
  ecto_repos: [Svc.Repo]

# Oban — фоновые задачи (E2: finalize absent; E3: уведомления)
config :svc, Oban,
  repo: Svc.Repo,
  queues: [default: 10, attendance: 5, notifications: 5],
  # D-020: сверка опубликованного манифеста приложения. В тестах Oban в режиме :manual —
  # плагины там не запускаются. Pruner сюда НЕ добавлять: ReminderWorker держит
  # unique: [period: :infinity] и опирается на уже выполненные джобы.
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"*/10 * * * *", Svc.AppReleases.AnnounceWorker}]}
  ]

# Cloak — шифрование полей at-rest (totp_secret). CLOAK_KEY из env в prod (CRED-CHECK).
config :svc, Svc.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1",
       key:
         Base.decode64!(
           System.get_env("CLOAK_KEY") || "dGhpc19pc19hX2Rldl9rZXlfMzJfYnl0ZXNfbG9uZyE="
         ),
       iv_length: 12}
  ]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :svc, Svc.Mailer, adapter: Swoosh.Adapters.Local

config :svc_web,
  ecto_repos: [Svc.Repo],
  generators: [context_app: :svc]

# i18n: локали интерфейса (uz/ru/en), по умолчанию — русский (исходный язык строк)
config :svc_web, SvcWeb.Gettext,
  default_locale: "ru",
  locales: ~w(en ru uz)

# Configures the endpoint
config :svc_web, SvcWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SvcWeb.ErrorHTML, json: SvcWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Svc.PubSub,
  live_view: [signing_salt: "yhveR1dp"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  svc_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/svc_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  svc_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/svc_web", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
