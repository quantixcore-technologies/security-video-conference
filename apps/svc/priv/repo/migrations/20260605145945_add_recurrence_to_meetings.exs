defmodule Svc.Repo.Migrations.AddRecurrenceToMeetings do
  use Ecto.Migration

  def change do
    alter table(:meetings) do
      # группа повторяющейся серии (uuid); nil для одиночных встреч
      add :recurrence_group, :string
    end

    create index(:meetings, [:recurrence_group])
  end
end
