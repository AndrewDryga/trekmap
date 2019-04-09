defmodule Trekmap.Me.Fleet do
  alias Trekmap.{APIClient, Session}
  require Logger

  defstruct id: nil,
            ship_id: nil,
            hull_id: nil,
            hull_type: nil,
            ship_crew: [],
            name: nil,
            system_id: nil,
            cargo_bay_size: nil,
            cargo_size: 0,
            protected_cargo_size: 0,
            strength: nil,
            hull_health: 100,
            shield_health: 100,
            coords: {0, 0},
            remaining_travel_time: 0,
            shield_regeneration_duration: nil,
            shield_regeneration_started_at: 0,
            max_warp_distance: nil,
            state: :at_dock,
            mining_node: nil

  @modify_fleet_endpoint "https://live-193-web.startrek.digitgaming.com/fleet/modify_fleet"
  @assign_fleet_officers_endpoint "https://live-193-web.startrek.digitgaming.com/officer/assign_fleet_officers"

  def build(deployed_fleet, %Session{} = session) do
    %{
      "fleet_id" => fleet_id,
      "fleet_data" => %{
        "cargo" => %{
          "resources" => resources
        },
        "cargo_max" => cargo_max,
        "crew_data" => crew_data
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
      "ship_ids" => [ship_id],
      "hull_ids" => [hull_id],
      "node_address" => %{
        "system" => system_id
      },
      "current_coords" => current_coords,
      "state" => state
    } = deployed_fleet

    destroyed? = Map.get(deployed_fleet, "is_destroyed", false)

    coords =
      case current_coords do
        %{"x" => x, "y" => y} -> {x, y}
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

    cargo_size = map_to_num(resources)

    ship_crew =
      Enum.map(crew_data, fn
        %{"id" => id} -> id
        nil -> -1
      end)

    %__MODULE__{
      id: fleet_id,
      ship_id: ship_id,
      ship_crew: ship_crew,
      hull_id: hull_id,
      hull_type: hull_type(hull_id, session),
      name: ship_name(ship_id),
      system_id: system_id,
      cargo_bay_size: cargo_max,
      cargo_size: cargo_size,
      protected_cargo_size: ship_protected_cargo(ship_id),
      strength: strength || ship_strength(ship_id),
      hull_health: hull_health,
      shield_health: shield_health,
      coords: coords,
      shield_regeneration_duration: map_to_num(ship_shield_total_regeneration_durations),
      max_warp_distance: warp_distance,
      remaining_travel_time: remaining_travel_time,
      state: state(state)
    }
  end

  def build(fleet_id, fleets, ships, %Session{} = session) do
    %{"ship_ids" => [ship_id], "officers" => officers} = Map.fetch!(fleets, to_string(fleet_id))

    ship_crew =
      Enum.map(officers, fn
        nil -> -1
        officer -> officer
      end)

    %{"max_hp" => max_hp, "hull_id" => hull_id, "damage" => damage} =
      Map.fetch!(ships, to_string(ship_id))

    hull_health = 100 - Enum.max([0, damage]) / (max_hp / 100)

    %__MODULE__{
      id: fleet_id,
      ship_id: ship_id,
      ship_crew: ship_crew,
      hull_id: hull_id,
      hull_type: hull_type(hull_id, session),
      name: ship_name(ship_id),
      system_id: session.home_system_id,
      hull_health: hull_health,
      strength: ship_strength(ship_id)
    }
  end

  defp map_to_num(map) do
    map
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  def fleet_setup_equals?(%__MODULE__{} = fleet, ship_id, preferred_crew) do
    crew_delta = preferred_crew -- fleet.ship_crew
    fleet.ship_id == ship_id and crew_delta == []
  end

  def assign_ship(dock_id, ship_id, session) do
    Logger.info("Assigning ship #{ship_name(ship_id)} to drydock ##{drydock_num(dock_id)}")
    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "ship_layout" => [ship_id],
        "fleet_id" => dock_id
      })

    with {:ok, _resp} <-
           APIClient.json_request(:post, @modify_fleet_endpoint, additional_headers, body) do
      :ok
    end
  end

  def assign_officers(dock_id, officers, session) do
    Logger.info("Assigning officers to ship at drydock ##{drydock_num(dock_id)}")
    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "officer_ids" => officers,
        "fleet_id" => dock_id
      })

    with {:ok, _resp} <-
           APIClient.json_request(
             :post,
             @assign_fleet_officers_endpoint,
             additional_headers,
             body
           ) do
      :ok
    end
  end

  defp state(6), do: :mining
  defp state(5), do: :mining
  defp state(3), do: :fighting
  defp state(2), do: :warping
  defp state(1), do: :flying
  defp state(0), do: :idle
  defp state(other), do: other

  def ship_id("Mayflower"), do: 834_523_813_579_670_645
  def ship_id("Vahklas"), do: 818_908_769_273_857_488
  def ship_id("Kehra"), do: 809_553_354_052_421_083
  def ship_id("North Star"), do: 793_228_477_045_490_952
  def ship_id("Kumari"), do: 822_579_326_280_352_768
  def ship_id("Saladin"), do: 842_689_708_634_228_174
  def ship_id("Envoy 1"), do: 788_241_743_887_025_466
  def ship_id("Envoy 2"), do: 813_554_350_852_228_185
  def ship_id("Envoy 3"), do: 824_733_744_035_612_116
  def ship_id("Horizon"), do: 829_530_915_272_475_702
  def ship_id("Phindra"), do: 774_102_373_647_074_543
  def ship_id("Fortunate"), do: 772_895_219_376_276_605
  def ship_id("Orion"), do: 771_326_161_581_327_453

  def ship_name(834_523_813_579_670_645), do: "Mayflower"
  def ship_name(818_908_769_273_857_488), do: "Vahklas"
  def ship_name(809_553_354_052_421_083), do: "Kehra"
  def ship_name(793_228_477_045_490_952), do: "North Star"
  def ship_name(822_579_326_280_352_768), do: "Kumari"
  def ship_name(842_689_708_634_228_174), do: "Saladin"
  def ship_name(788_241_743_887_025_466), do: "Envoy 1"
  def ship_name(813_554_350_852_228_185), do: "Envoy 2"
  def ship_name(824_733_744_035_612_116), do: "Envoy 3"
  def ship_name(829_530_915_272_475_702), do: "Horizon"
  def ship_name(774_102_373_647_074_543), do: "Phindra"
  def ship_name(772_895_219_376_276_605), do: "Fortunate"
  def ship_name(771_326_161_581_327_453), do: "Orion"
  def ship_name(ship_id), do: ship_id

  def ship_strength(834_523_813_579_670_645), do: 480_000
  def ship_strength(818_908_769_273_857_488), do: 217_000
  def ship_strength(809_553_354_052_421_083), do: 160_000
  def ship_strength(793_228_477_045_490_952), do: 293_000
  def ship_strength(822_579_326_280_352_768), do: 286_000
  def ship_strength(842_689_708_634_228_174), do: 300_000
  def ship_strength(788_241_743_887_025_466), do: 50_000
  def ship_strength(813_554_350_852_228_185), do: 50_000
  def ship_strength(824_733_744_035_612_116), do: 50_000
  def ship_strength(829_530_915_272_475_702), do: 150_000
  def ship_strength(774_102_373_647_074_543), do: 25_000
  def ship_strength(772_895_219_376_276_605), do: 20_000
  def ship_strength(771_326_161_581_327_453), do: 20_000
  def ship_strength(_ship_id), do: 200_000

  def ship_protected_cargo(834_523_813_579_670_645), do: 790
  def ship_protected_cargo(818_908_769_273_857_488), do: 580
  def ship_protected_cargo(809_553_354_052_421_083), do: 474
  def ship_protected_cargo(793_228_477_045_490_952), do: 1320
  def ship_protected_cargo(822_579_326_280_352_768), do: 580
  def ship_protected_cargo(842_689_708_634_228_174), do: 436
  def ship_protected_cargo(788_241_743_887_025_466), do: 10_000
  def ship_protected_cargo(813_554_350_852_228_185), do: 10_000
  def ship_protected_cargo(824_733_744_035_612_116), do: 10_000
  def ship_protected_cargo(829_530_915_272_475_702), do: 9945
  def ship_protected_cargo(774_102_373_647_074_543), do: 0
  def ship_protected_cargo(772_895_219_376_276_605), do: 0
  def ship_protected_cargo(771_326_161_581_327_453), do: 0
  def ship_protected_cargo(_ship_id), do: 0

  def hull_type(hull_id, %{game_config: %{hull_specs: hull_specs}}),
    do: hull_specs |> Map.fetch!(hull_id) |> Map.fetch!("type") |> hull_type_name()

  def hull_type_name(0), do: :interceptor
  def hull_type_name(1), do: :survey
  def hull_type_name(2), do: :explorer
  def hull_type_name(3), do: :battleship
  def hull_type_name(4), do: :station_defence_system

  def hull_power_ratio(:explorer, :interceptor), do: 1.3
  def hull_power_ratio(:interceptor, :battleship), do: 1.3
  def hull_power_ratio(:battleship, :explorer), do: 1.3
  def hull_power_ratio(:survey, _), do: 0.8
  def hull_power_ratio(_, _), do: 1

  def drydock_num(771_246_931_724_024_704), do: 1
  def drydock_num(771_331_774_860_311_262), do: 2
  def drydock_num(791_687_022_921_464_764), do: 3
  def drydock_num(838_875_307_527_453_592), do: 4

  def drydock1_id, do: 771_246_931_724_024_704
  def drydock2_id, do: 771_331_774_860_311_262
  def drydock3_id, do: 791_687_022_921_464_764
  def drydock4_id, do: 838_875_307_527_453_592

  def drydocs, do: [drydock1_id(), drydock2_id(), drydock3_id(), drydock4_id()]
end
