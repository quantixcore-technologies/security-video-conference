defmodule Svc.Vault do
  @moduledoc "Cloak Vault — шифрование чувствительных полей at-rest (D-010/D-014)."
  use Cloak.Vault, otp_app: :svc
end
