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
    at = DateTime.utc_now()

    {spoofing, spoof_reason} =
      detect_spoofing(org_id, opts[:user_id], opts[:gps_lat], opts[:gps_lon], at)

    # E7-spoofing: подмена геолокации поднимает allow → flag (block не трогаем; D-012 fail-open)
    {decision, reason} =
      if spoofing and decision == :allow,
        do: {:flag, "Подозрение на подмену геолокации: #{spoof_reason}"},
        else: {decision, reason}

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
        gps_accuracy: opts[:gps_accuracy],
        checked_at: at,
        spoofing: spoofing,
        spoofing_reason: spoof_reason
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

  @doc "Число проверок с подозрением на подмену геолокации (E7-spoofing)."
  def spoofing_count(org_id) do
    Repo.aggregate(
      from(c in NetworkGeoCheck, where: c.org_id == ^org_id and c.spoofing == true),
      :count
    )
  end

  # --- E7-spoofing: детект «невозможного перемещения» по GPS-истории ---

  # airplane-скорость как порог «невозможного» перемещения
  @spoof_max_speed_kmh 900.0
  # игнорируем дрожание GPS (< 25 км между точками)
  @spoof_min_distance_km 25.0

  @doc """
  Детект подмены геолокации (impossible-travel): сравнивает текущий GPS с последним
  прошлым GPS-чеком пользователя. {spoofing?, reason}. Без GPS/истории — {false, nil}.
  Перемещение > 25 км с невозможной скоростью (> 900 км/ч) ⇒ подмена.
  """
  def detect_spoofing(org_id, user_id, lat, lon, at)
      when is_integer(user_id) and is_number(lat) and is_number(lon) do
    case last_gps_check(org_id, user_id) do
      %NetworkGeoCheck{gps_lat: plat, gps_lon: plon, checked_at: pat}
      when is_number(plat) and is_number(plon) ->
        classify_travel(
          haversine_km(plat, plon, lat, lon),
          DateTime.diff(at, pat, :second) / 3600.0
        )

      _ ->
        {false, nil}
    end
  end

  def detect_spoofing(_org_id, _user_id, _lat, _lon, _at), do: {false, nil}

  # Классификация перемещения (расстояние км + время ч) → {spoofing?, reason}.
  defp classify_travel(dist, _hours) when dist < @spoof_min_distance_km, do: {false, nil}

  defp classify_travel(dist, hours) when hours <= 0,
    do: {true, "мгновенное перемещение на #{trunc(dist)} км"}

  defp classify_travel(dist, hours) do
    speed = dist / hours

    if speed > @spoof_max_speed_kmh do
      {true,
       "невозможная скорость #{trunc(speed)} км/ч (#{trunc(dist)} км за #{Float.round(hours, 2)} ч)"}
    else
      {false, nil}
    end
  end

  @doc "Расстояние между двумя GPS-точками (км, формула гаверсинусов)."
  def haversine_km(lat1, lon1, lat2, lon2) do
    r = 6371.0
    dlat = deg2rad(lat2 - lat1)
    dlon = deg2rad(lon2 - lon1)
    slat = :math.sin(dlat / 2)
    slon = :math.sin(dlon / 2)
    a = slat * slat + :math.cos(deg2rad(lat1)) * :math.cos(deg2rad(lat2)) * slon * slon
    r * 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1.0 - a))
  end

  defp deg2rad(d), do: d * :math.pi() / 180.0

  defp last_gps_check(org_id, user_id) do
    Repo.one(
      from c in NetworkGeoCheck,
        where:
          c.org_id == ^org_id and c.user_id == ^user_id and
            not is_nil(c.gps_lat) and not is_nil(c.gps_lon),
        order_by: [desc: c.checked_at, desc: c.id],
        limit: 1
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
