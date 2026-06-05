defmodule Svc.Geo do
  @moduledoc """
  Сеть/гео pre-join gate (E7, D-012).

  ⚠️ Честная рамка: реальный VPN/proxy/country-детект требует MaxMind MMDB-баз
  (через `locus`, self-host) — лицензия = открытый вопрос заказчику. До их загрузки
  MVP делает базовую IP-классификацию (private/public) и журналирует решения;
  публичные IP помечаются `flag` («гео-данные недоступны»), а не блокируются вслепую.

  Архитектура (gate + журнал + decision) готова: подключение `locus` заменит
  `classify_ip/1` на реальный country + Anonymous-IP lookup без смены интерфейса.
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Geo.NetworkGeoCheck

  @doc """
  Pre-join проверка IP: классифицирует + записывает в журнал.
  Возвращает {:allow | :block | :flag, reason}.
  opts: :meeting_id, :user_id.
  """
  def gate(org_id, ip, opts \\ []) when is_binary(ip) do
    {decision, reason, attrs} = classify_ip(ip)

    record_check(
      Map.merge(attrs, %{
        org_id: org_id,
        meeting_id: opts[:meeting_id],
        user_id: opts[:user_id],
        ip: ip,
        decision: to_string(decision),
        reason: reason
      })
    )

    {decision, reason}
  end

  @doc "Классификация IP (без записи). MVP: private → allow, public → flag (нужна MMDB)."
  def classify_ip(ip) when is_binary(ip) do
    if private_ip?(ip) do
      {:allow, "Локальная/внутренняя сеть", %{ip_country: "LOCAL"}}
    else
      {:flag, "Гео-данные недоступны (MMDB не загружена) — требуется ручная проверка",
       %{ip_country: nil}}
    end
  end

  def record_check(attrs) do
    attrs = Map.put_new(attrs, :checked_at, DateTime.utc_now())

    %NetworkGeoCheck{}
    |> NetworkGeoCheck.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Журнал гео-проверок организации (свежие сверху)."
  def list_checks(org_id, opts \\ []) do
    limit = opts[:limit] || 50

    Repo.all(
      from c in NetworkGeoCheck,
        where: c.org_id == ^org_id,
        order_by: [desc: c.checked_at, desc: c.id],
        limit: ^limit
    )
  end

  @doc "Число заблокированных/флагнутых проверок (для метрик безопасности)."
  def flagged_count(org_id) do
    Repo.aggregate(
      from(c in NetworkGeoCheck, where: c.org_id == ^org_id and c.decision in [:block, :flag]),
      :count
    )
  end

  # --- IP-классификация (MVP, RFC 1918 + loopback) ---

  defp private_ip?(ip) do
    cond do
      ip in ["127.0.0.1", "::1", "localhost"] -> true
      String.starts_with?(ip, "10.") -> true
      String.starts_with?(ip, "192.168.") -> true
      private_172?(ip) -> true
      true -> false
    end
  end

  defp private_172?(ip) do
    case String.split(ip, ".") do
      ["172", second | _] ->
        case Integer.parse(second) do
          {n, _} when n >= 16 and n <= 31 -> true
          _ -> false
        end

      _ ->
        false
    end
  end
end
