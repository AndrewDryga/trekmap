defmodule Trekmap.Me.Fleet.Setups do
  def other_time_officers do
    [
      1_622_062_016,
      1_525_867_544,
      194_631_754,
      1_853_520_303,
      4_066_988_596,
      4_150_311_506,
      3_394_864_658,
      2_865_735_742,
      2_518_604_778,
      -1
    ]
  end

  def other_time_long_warp_officers do
    [
      1_622_062_016,
      1_525_867_544,
      4_150_311_506,
      1_853_520_303,
      4_066_988_596,
      194_631_754,
      3_394_864_658,
      2_865_735_742,
      2_518_604_778,
      -1
    ]
  end

  def enterprise_crew_officers do
    [
      988_947_581,
      2_695_272_429,
      766_809_588,
      2_520_801_863,
      3_155_244_352,
      3_923_643_019,
      2_765_885_322,
      250_991_574,
      -1,
      -1
    ]
  end

  def glory_in_kill_officers do
    [
      3_394_864_658,
      2_517_597_941,
      680_147_223,
      339_936_167,
      98_548_875,
      2_235_857_051,
      2_601_201_375,
      176_044_746,
      -1,
      -1
    ]
  end

  def nero_crew_officers do
    [
      656_972_203,
      1_983_456_684,
      2_959_514_562,
      2_235_857_051,
      668_528_267,
      339_936_167,
      680_147_223,
      2_601_201_375,
      -1,
      -1
    ]
  end

  def lower_deck_officers do
    [
      4_219_901_626,
      407_568_868,
      2_775_384_983,
      3_221_819_893,
      1_455_040_265,
      2_567_136_252,
      -1,
      -1,
      -1,
      -1
    ]
  end

  def raid_transport_officers do
    [
      755_079_845,
      3_816_036_121,
      3_156_736_320,
      339_936_167,
      98_548_875,
      2_235_857_051,
      2_601_201_375,
      176_044_746,
      -1,
      -1
    ]
  end

  def weak_raid_transport_officers do
    [
      755_079_845,
      3_816_036_121,
      3_156_736_320,
      4_219_901_626,
      407_568_868,
      2_775_384_983,
      3_221_819_893,
      176_044_746,
      -1,
      -1
    ]
  end

  # Group 1

  def mayflower_set do
    [
      ship: "Mayflower",
      crew: enterprise_crew_officers(),
      max_warp_distance: 33
    ]
  end

  def north_star_set do
    [
      ship: "North Star",
      crew: other_time_officers(),
      max_warp_distance: 39
    ]
  end

  def north_star_with_long_warp_set do
    [
      ship: "North Star",
      crew: other_time_long_warp_officers(),
      max_warp_distance: 43
    ]
  end

  def kumari_set do
    [
      ship: "Kumari",
      crew: nero_crew_officers(),
      max_warp_distance: 26
    ]
  end

  def saladin_with_station_defence_set do
    [
      ship: "Saladin",
      crew: lower_deck_officers(),
      max_warp_distance: 23
    ]
  end

  def vahklas_with_station_defence_set do
    [
      ship: "Vahklas",
      crew: lower_deck_officers(),
      max_warp_distance: 23
    ]
  end

  # Group 2

  def phindra_set do
    [
      ship: "Phindra",
      crew: other_time_officers(),
      max_warp_distance: 13
    ]
  end

  def fortunate_set do
    [
      ship: "Fortunate",
      crew: nero_crew_officers(),
      max_warp_distance: 13
    ]
  end

  def orion_set do
    [
      ship: "Orion",
      crew: lower_deck_officers(),
      max_warp_distance: 8
    ]
  end

  # Group 3

  def envoy1_set do
    [
      ship: "Envoy 1",
      crew: enterprise_crew_officers(),
      max_warp_distance: 22
    ]
  end

  def envoy2_set do
    [
      ship: "Envoy 2",
      crew: other_time_officers(),
      max_warp_distance: 22
    ]
  end

  def envoy3_set do
    [
      ship: "Envoy 3",
      crew: lower_deck_officers(),
      max_warp_distance: 22
    ]
  end

  def horizon_set do
    [
      ship: "Horizon",
      crew: raid_transport_officers(),
      max_warp_distance: 27
    ]
  end

  def weak_horizon_set do
    [
      ship: "Horizon",
      crew: weak_raid_transport_officers(),
      max_warp_distance: 27
    ]
  end
end
