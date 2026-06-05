defmodule Svc.GeoTest do
  use Svc.DataCase, async: true

  alias Svc.{Geo, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    %{org: org}
  end

  test "classify_ip: приватные IP → allow (LOCAL)" do
    assert {:allow, _, %{ip_country: "LOCAL"}} = Geo.classify_ip("192.168.1.5")
    assert {:allow, _, _} = Geo.classify_ip("127.0.0.1")
    assert {:allow, _, _} = Geo.classify_ip("10.0.0.1")
    assert {:allow, _, _} = Geo.classify_ip("172.16.0.1")
    assert {:allow, _, _} = Geo.classify_ip("172.31.255.1")
  end

  test "classify_ip: публичные IP → flag (нет MMDB)" do
    assert {:flag, _, _} = Geo.classify_ip("8.8.8.8")
    # 172.32 вне приватного диапазона 172.16-31
    assert {:flag, _, _} = Geo.classify_ip("172.32.0.1")
  end

  test "gate записывает проверку в журнал", %{org: org} do
    assert {:allow, _} = Geo.gate(org.id, "192.168.1.1")
    assert [check] = Geo.list_checks(org.id)
    assert check.decision == :allow
    assert check.ip == "192.168.1.1"
    assert check.ip_country == "LOCAL"
  end

  test "gate публичного IP → flag + flagged_count", %{org: org} do
    assert {:flag, _} = Geo.gate(org.id, "8.8.8.8")
    assert Geo.flagged_count(org.id) == 1
  end

  test "list_checks изолирован по org (D-005)", %{org: org} do
    {:ok, other} = Orgs.create_organization(%{name: "Чужое", slug: "ch"})
    Geo.gate(other.id, "8.8.8.8")
    assert Geo.list_checks(org.id) == []
  end

  describe "гео-политика (E7-B)" do
    test "get_policy возвращает дефолт если не настроена", %{org: org} do
      p = Geo.get_policy(org.id)
      assert p.mode == :flag_only
      assert p.allowed_countries == ["UZ"]
    end

    test "upsert_policy создаёт и обновляет (одна на org)", %{org: org} do
      assert {:ok, p} = Geo.upsert_policy(org.id, %{"mode" => "enforce", "allowed_countries" => ["UZ", "KZ"]})
      assert p.mode == :enforce
      assert {:ok, p2} = Geo.upsert_policy(org.id, %{"mode" => "off"})
      assert p2.mode == :off
      assert Geo.get_policy(org.id).mode == :off
    end

    test "mode off → gate всегда allow (даже публичный IP)", %{org: org} do
      Geo.upsert_policy(org.id, %{"mode" => "off"})
      assert {:allow, _} = Geo.gate(org.id, "8.8.8.8")
    end

    test "whitelist_ips → allow для публичного IP", %{org: org} do
      Geo.upsert_policy(org.id, %{"mode" => "flag_only", "whitelist_ips" => ["8.8.8.8"]})
      assert {:allow, _} = Geo.gate(org.id, "8.8.8.8")
    end
  end
end
