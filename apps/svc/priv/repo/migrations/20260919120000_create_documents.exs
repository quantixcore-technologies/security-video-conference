defmodule Svc.Repo.Migrations.CreateDocuments do
  @moduledoc """
  S40 — обмен документами.

  Файл НЕ хранится в БД: на диск кладётся зашифрованный блоб, в таблице —
  только метаданные и ключ хранения. Причины: (1) дампы БД остаются мелкими и
  быстрыми (их же гоняет почасовой бэкап), (2) поток скачивания не тянет
  мегабайты через Postgres.

  Доступ: `org_id` (D-005) + явный список получателей. Как и во встречах
  (D-016/D-021), невидимый документ отдаётся как «не найден».
  """
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :owner_id, references(:users, on_delete: :restrict), null: false

      add :title, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string
      add :byte_size, :bigint, null: false

      # Контроль целостности: считается до шифрования, сверяется после расшифровки.
      add :sha256, :string, null: false

      # Имя файла на диске (uuid). Путь собирается из конфига, чтобы каталог
      # можно было перенести, не трогая БД.
      add :storage_key, :string, null: false

      # Версионирование: новая версия ссылается на корневой документ.
      add :version, :integer, null: false, default: 1
      add :parent_id, references(:documents, on_delete: :nilify_all)

      # Срок доступа и отзыв — оба в спеке «expiry & revocation».
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:documents, [:org_id])
    create index(:documents, [:owner_id])
    create index(:documents, [:parent_id])
    create unique_index(:documents, [:storage_key])

    create table(:document_recipients) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Когда получатель впервые скачал — для «кто прочитал» и форензики.
      add :opened_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_recipients, [:document_id, :user_id])
    create index(:document_recipients, [:user_id])
    create index(:document_recipients, [:org_id])
  end
end
