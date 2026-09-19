defmodule Svc.Documents.Storage do
  @moduledoc """
  Хранилище файлов документов: на диске лежит только ЗАШИФРОВАННЫЙ блоб (S40).

  Шифрование — тем же `Svc.Vault` (AES-GCM, ключ из `CLOAK_KEY`), что и
  `totp_secret`: один ключ, одна процедура ротации, никакой самодеятельной
  криптографии. Отдельного ключа для файлов нет намеренно — иначе появился бы
  второй секрет, который надо где-то хранить и ротировать.

  Почему не в БД: почасовой дамп `pg_dumpall` уезжает в Borg, и мегабайты
  вложений раздували бы его на каждом прогоне.

  Почему не в `priv/static/uploads` (как фото сотрудников): та папка отдаётся
  `Plug.Static` БЕЗ аутентификации — для документов это утечка. Каталог задаётся
  `config :svc, :documents_dir` и лежит вне веб-корня.
  """

  alias Svc.Vault

  @doc "Каталог хранения. В тестах/дев — под tmp, в проде задаётся конфигом."
  def dir do
    Application.get_env(:svc, :documents_dir) ||
      Path.join(System.tmp_dir!(), "svc-documents-#{Mix.env()}")
  end

  @doc """
  Кладёт содержимое на диск в зашифрованном виде.

  Возвращает `{:ok, storage_key}`. Имя файла — случайное (не из `client_name`),
  поэтому path traversal через имя загружаемого файла невозможен в принципе.
  """
  def put(content) when is_binary(content) do
    key = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    with {:ok, encrypted} <- encrypt(content),
         :ok <- File.mkdir_p(dir()),
         :ok <- File.write(path(key), encrypted) do
      {:ok, key}
    end
  end

  @doc "Читает и расшифровывает. `{:error, :not_found}` — если блоб пропал."
  def get(key) when is_binary(key) do
    case File.read(path(key)) do
      {:ok, encrypted} -> decrypt(encrypted)
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Физически удаляет блоб.

  Вызывается только при откате неудачной загрузки: отзыв документа (`revoke`)
  файл НЕ удаляет — запись должна оставаться воспроизводимой для аудита.
  """
  def delete(key) when is_binary(key) do
    case File.rm(path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc "Полный путь к блобу. Ключ генерируем мы сами, но проверяем его форму."
  def path(key) when is_binary(key) do
    unless valid_key?(key), do: raise(ArgumentError, "некорректный storage_key")
    Path.join(dir(), key)
  end

  defp valid_key?(key), do: String.match?(key, ~r/\A[A-Za-z0-9_-]{16,64}\z/)

  defp encrypt(content) do
    {:ok, Vault.encrypt!(content)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp decrypt(encrypted) do
    {:ok, Vault.decrypt!(encrypted)}
  rescue
    # Испорченный/подменённый блоб не должен ронять запрос: AES-GCM здесь
    # работает и как контроль подлинности — расшифровка чужого байта упадёт.
    error -> {:error, Exception.message(error)}
  end
end
