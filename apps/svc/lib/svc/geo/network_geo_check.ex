defmodule Svc.Geo.NetworkGeoCheck do
  @moduledoc "Запись pre-join сетевой/гео-проверки (E7). Append-only журнал, scoped по org_id."
  use Ecto.Schema
  import Ecto.Changeset

  @decisions ~w(allow block flag)a

  @type t :: %__MODULE__{}

  schema "network_geo_checks" do
    field :ip, :string
    field :ip_country, :string
    field :is_vpn, :boolean, default: false
    field :is_proxy, :boolean, default: false
    field :is_hosting, :boolean, default: false
    field :decision, Ecto.Enum, values: @decisions
    field :reason, :string
    field :mmdb_version, :string
    field :checked_at, :utc_datetime_usec

    # GPS от нативного клиента (E7): координаты на момент join (могут отсутствовать).
    field :gps_lat, :float
    field :gps_lon, :float
    field :gps_accuracy, :float

    # E7-spoofing: подозрение на подмену геолокации (impossible-travel)
    field :spoofing, :boolean, default: false
    field :spoofing_reason, :string

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :meeting, Svc.Meetings.Meeting
    belongs_to :user, Svc.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def decisions, do: @decisions

  def changeset(check, attrs) do
    check
    |> cast(attrs, [
      :org_id,
      :meeting_id,
      :user_id,
      :ip,
      :ip_country,
      :is_vpn,
      :is_proxy,
      :is_hosting,
      :decision,
      :reason,
      :mmdb_version,
      :checked_at,
      :gps_lat,
      :gps_lon,
      :gps_accuracy,
      :spoofing,
      :spoofing_reason
    ])
    |> validate_required([:org_id, :ip, :decision, :checked_at])
    |> foreign_key_constraint(:org_id)
  end
end
