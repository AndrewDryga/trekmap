defmodule Trekmap.Me.Fleet do
  defstruct id: nil,
            system_id: nil,
            cargo_bay_size: nil,
            cargo_size: nil,
            strength: nil,
            hull_health: 100,
            shield_health: 100,
            coords: {0, 0},
            remaining_travel_time: 0,
            shield_regeneration_duration: nil,
            max_warp_distance: nil,
            warp_time: nil,
            state: :at_dock

  def build(deployed_fleet) do
    %{
      "fleet_id" => fleet_id,
      "fleet_data" => %{
        "cargo" => %{
          "resources" => resources
        },
        "cargo_max" => cargo_max
      },
      "officer_rating" => officer_rating,
      "offense_rating" => offense_rating,
      "defense_rating" => defense_rating,
      "health_rating" => health_rating,
      "warp_distance" => warp_distance,
      "ship_shield_dmg" => ship_shield_dmg,
      "ship_shield_hps" => ship_shield_hps,
      "ship_shield_total_regeneration_durations" => ship_shield_total_regeneration_durations,
      "ship_dmg" => ship_dmg,
      "ship_hps" => ship_hps,
      "node_address" => %{
        "system" => system_id
      },
      "current_coords" => current_coords,
      "warp_time" => warp_time,
      "state" => state
    } = deployed_fleet

    destroyed? = Map.get(deployed_fleet, "is_destroyed", false)

    coords =
      case current_coords do
        %{"y" => x, "x" => y} -> {x, y}
        nil -> {0, 0}
      end

    remaining_travel_time =
      case Map.get(deployed_fleet, "current_course") do
        %{"start_time" => source_start_time, "duration" => duration} ->
          remaining_travel_time =
            NaiveDateTime.diff(
              NaiveDateTime.add(
                NaiveDateTime.from_iso8601!(source_start_time),
                duration,
                :second
              ),
              NaiveDateTime.utc_now(),
              :second
            )

          Enum.max([0, remaining_travel_time])

        _other ->
          0
      end

    hull_health = map_to_num(ship_hps)
    hull_damage = map_to_num(ship_dmg)

    hull_health =
      if destroyed?, do: 0, else: 100 - Enum.max([0, hull_damage]) / (hull_health / 100)

    shield_health = map_to_num(ship_shield_hps)
    shield_damage = map_to_num(ship_shield_dmg)

    shield_health =
      if destroyed?, do: 0, else: 100 - Enum.max([0, shield_damage]) / (shield_health / 100)

    strength =
      (officer_rating + offense_rating + defense_rating + health_rating) * (hull_health / 100)

    warp_time =
      case NaiveDateTime.from_iso8601(warp_time || "") do
        %NaiveDateTime{} = dt -> dt
        _other -> nil
      end

    %__MODULE__{
      id: fleet_id,
      system_id: system_id,
      cargo_bay_size: cargo_max,
      cargo_size: map_to_num(resources),
      strength: strength,
      hull_health: hull_health,
      shield_health: shield_health,
      coords: coords,
      shield_regeneration_duration: map_to_num(ship_shield_total_regeneration_durations),
      max_warp_distance: warp_distance,
      warp_time: warp_time,
      remaining_travel_time: remaining_travel_time,
      state: state(state)
    }
  end

  defp map_to_num(map) do
    map
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  defp state(6), do: :mining
  defp state(5), do: :mining
  defp state(3), do: :fighting
  defp state(2), do: :warping
  defp state(1), do: :flying
  defp state(0), do: :idle
  defp state(other), do: other

  def jellyfish_fleet_id, do: 771_246_931_724_024_704
  def northstar_fleet_id, do: 771_331_774_860_311_262
end
