defmodule Svc.Repo.Migrations.AddActionToDocuments do
  @moduledoc """
  S41 — «от кого и что с этим делать».

  В госдокументообороте файл почти никогда не приходит «просто так»: к нему
  прилагается резолюция — к сведению / на рассмотрение / на подпись / на
  исполнение — и обычно срок. Без этого получатель видит список файлов и не
  понимает, какой из них требует действия.

  `acknowledged_at` у получателя — отметка «ознакомился / исполнил»: отправителю
  нужно видеть не только «скачал», но и «принял к исполнению».
  """
  use Ecto.Migration

  def change do
    alter table(:documents) do
      # information | review | signature | execution
      add :action, :string, null: false, default: "information"
      add :note, :text
      add :due_at, :utc_datetime_usec
    end

    alter table(:document_recipients) do
      add :acknowledged_at, :utc_datetime_usec
    end

    create index(:documents, [:org_id, :action])
  end
end
