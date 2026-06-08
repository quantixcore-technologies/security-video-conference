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
  alias Svc.Geo.{NetworkGeoCheck, GeoPolicy}

  @doc "Гео-политика организации (или дефолт flag_only/UZ, если не настроена)."
  def get_policy(org_id) do
    Repo.get_by(GeoPolicy, org_id: org_id) ||
      %GeoPolicy{
        org_id: org_id,
        mode: :flag_only,
        allowed_countries: ["UZ"],
        block_vpn: true,
        block_proxy: true,
        whitelist_ips: []
      }
  end

  @doc "Changeset для формы политики."
  def change_policy(%GeoPolicy{} = policy, attrs \\ %{}), do: GeoPolicy.changeset(policy, attrs)

  @doc "Создаёт/обновляет гео-политику организации."
  def upsert_policy(org_id, attrs) do
    base = Repo.get_by(GeoPolicy, org_id: org_id) || %GeoPolicy{}

    base
    |> GeoPolicy.changeset(Map.put(attrs, "org_id", org_id))
    |> Repo.insert_or_update()
  end

  @doc """
  Pre-join проверка IP с учётом гео-политики org: классифицирует + журналирует.
  Возвращает {:allow | :block | :flag, reason}.
  opts: :meeting_id, :user_id, :gps_lat, :gps_lon, :gps_accuracy (от нативного клиента).
  """
  def gate(org_id, ip, opts \\ []) when is_binary(ip) do
    {decision, reason, attrs} = decide(ip, get_policy(org_id))

    record_check(
      Map.merge(attrs, %{
        org_id: org_id,
        meeting_id: opts[:meeting_id],
        user_id: opts[:user_id],
        ip: ip,
        decision: to_string(decision),
        reason: reason,
        gps_lat: opts[:gps_lat],
        gps_lon: opts[:gps_lon],
        gps_accuracy: opts[:gps_accuracy]
      })
    )

    {decision, reason}
  end

  @doc "Классификация IP с дефолтной политикой (flag_only) — без записи."
  def classify_ip(ip) when is_binary(ip),
    do: decide(ip, %GeoPolicy{mode: :flag_only, whitelist_ips: []})

  # Решение по IP + политике. MVP: private/whitelist → allow, public → flag (нужна MMDB),
  # mode off → всё allow. Реальный VPN/country block — после подключения MMDB (locus).
  defp decide(ip, policy) do
    cond do
      policy.mode == :off ->
        {:allow, "Гео-проверка отключена политикой", %{ip_country: nil}}

      ip in (policy.whitelist_ips || []) ->
        {:allow, "IP в whitelist организации", %{ip_country: nil}}

      private_ip?(ip) ->
        {:allow, "Локальная/внутренняя сеть", %{ip_country: "LOCAL"}}

      true ->
        {:flag, "Гео-данные недоступны (MMDB не загружена) — ручная проверка", %{ip_country: nil}}
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
