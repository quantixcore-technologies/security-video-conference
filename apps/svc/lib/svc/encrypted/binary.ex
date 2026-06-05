defmodule Svc.Encrypted.Binary do
  @moduledoc "Ecto-тип: шифрованный binary через Svc.Vault (для totp_secret и т.п.)."
  use Cloak.Ecto.Binary, vault: Svc.Vault
end
