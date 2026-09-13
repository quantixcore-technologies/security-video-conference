defmodule Svc.AppReleases.Announcement do
  @moduledoc """
  Отметка «версия приложения объявлена пользователям» (D-020).

  Уникальность `platform + version_code` на уровне базы и есть гарантия «ровно одно
  уведомление на релиз»: вторая вставка той же версии просто не произойдёт.
  """
  use Ecto.Schema
  import Ecto.Changeset

  # iOS добавится сюда, когда сборки начнут распространяться (сейчас build 1 «готовится»).
  @platforms ~w(android)

  schema "app_release_announcements" do
    field :platform, :string
    field :version_code, :integer
    field :version_name, :string
    field :notified_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(announcement, attrs) do
    announcement
    |> cast(attrs, [:platform, :version_code, :version_name, :notified_count])
    |> validate_required([:platform, :version_code])
    |> validate_inclusion(:platform, @platforms)
    |> validate_number(:version_code, greater_than: 0)
    |> unique_constraint([:platform, :version_code])
  end
end
