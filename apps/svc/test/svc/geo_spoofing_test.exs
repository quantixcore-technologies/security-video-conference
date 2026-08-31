defmodule Svc.GeoSpoofingTest do
  @moduledoc "E7-spoofing: детект подмены геолокации (impossible-travel по GPS-истории)."
  use Svc.DataCase, async: true

  alias Svc.{Geo, Orgs, Accounts}

  @tashkent {41.31, 69.24}
  @london {51.50, -0.12}
  # ~5 км от @tashkent
  @tashkent2 {41.35, 69.29}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-spoof"})

    {:ok, user} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "usr",
        full_name: "User",
        password: "SecurePass123!",
        role: :employee
      })

    %{org: org, user: user}
  end

  defp seed_gps(org, user, {lat, lon}, at) do
    {:ok, _} =
      Geo.record_check(%{
        org_id: org.id,
        user_id: user.id,
        ip: "10.0.0.1",
        decision: "allow",
        checked_at: at,
        gps_lat: lat,
        gps_lon: lon
      })
  end

  describe "haversine_km/4" do
    test "Ташкент → Лондон ≈ 5900 км" do
      {la1, lo1} = @tashkent
      {la2, lo2} = @london
      d = Geo.haversine_km(la1, lo1, la2, lo2)
      assert d > 5000 and d < 6500
    end

    test "близкие точки < 10 км" do
      {la1, lo1} = @tashkent
      {la2, lo2} = @tashkent2
      assert Geo.haversine_km(la1, lo1, la2, lo2) < 10
    end
  end

  describe "detect_spoofing/5" do
    test "нет истории → {false, nil}", %{org: org, user: user} do
      {la, lo} = @tashkent
      assert Geo.detect_spoofing(org.id, user.id, la, lo, DateTime.utc_now()) == {false, nil}
    end

    test "Ташкент → Лондон за минуту → spoof", %{org: org, user: user} do
      t0 = DateTime.utc_now()
      seed_gps(org, user, @tashkent, t0)

      {la, lo} = @london
      t1 = DateTime.add(t0, 60, :second)
      assert {true, reason} = Geo.detect_spoofing(org.id, user.id, la, lo, t1)
      assert is_binary(reason)
    end

    test "нормальное перемещение по городу за час → {false, nil}", %{org: org, user: user} do
      t0 = DateTime.utc_now()
      seed_gps(org, user, @tashkent, t0)

      {la, lo} = @tashkent2
      t1 = DateTime.add(t0, 3600, :second)
      assert Geo.detect_spoofing(org.id, user.id, la, lo, t1) == {false, nil}
    end

    test "история другого пользователя не влияет", %{org: org, user: user} do
      seed_gps(org, user, @tashkent, DateTime.utc_now())

      {:ok, other} =
        Accounts.create_user(%{
          org_id: org.id,
          username: "othr",
          full_name: "Other",
          password: "SecurePass123!",
          role: :employee
        })

      {la, lo} = @london
      assert Geo.detect_spoofing(org.id, other.id, la, lo, DateTime.utc_now()) == {false, nil}
    end

    test "без GPS-координат → {false, nil}", %{org: org, user: user} do
      assert Geo.detect_spoofing(org.id, user.id, nil, nil, DateTime.utc_now()) == {false, nil}
    end
  end

  describe "gate/3 integration" do
    test "спуфинг поднимает allow → flag и пишет spoofing=true", %{org: org, user: user} do
      {la1, lo1} = @tashkent

      assert {:allow, _} =
               Geo.gate(org.id, "10.0.0.5", user_id: user.id, gps_lat: la1, gps_lon: lo1)

      {la2, lo2} = @london

      assert {:flag, reason} =
               Geo.gate(org.id, "10.0.0.5", user_id: user.id, gps_lat: la2, gps_lon: lo2)

      assert reason =~ "подмену геолокации"
      assert Geo.spoofing_count(org.id) == 1
    end
  end
end
