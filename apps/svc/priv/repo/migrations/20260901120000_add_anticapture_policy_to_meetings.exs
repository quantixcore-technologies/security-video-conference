defmodule Svc.Repo.Migrations.AddAnticapturePolicyToMeetings do
  use Ecto.Migration

  # E5-C: пер-встречная анти-захват политика.
  # watermark_enabled — показывать ли per-user watermark на звонке.
  # capture_reaction  — реакция на детект захвата: none | warn | eject.
  def change do
    alter table(:meetings) do
      add :watermark_enabled, :boolean, null: false, default: true
      add :capture_reaction, :string, null: false, default: "none"
    end
  end
end
