defmodule Trekmap.Galaxy.Spacecraft do
  @behaviour Trekmap.AirDB

  defstruct external_id: nil,
            system: nil,
            player: nil,
            id: nil,
            strength: nil,
            hull_type: nil,
            bounty_score: nil,
            coords: {0, 0},
            mining_node: nil,
            pursuit_fleet_id: nil

  def table_name, do: "Spacecrafts"

  def struct_to_record(%__MODULE__{} = spacecraft) do
    %{
      id: id,
      player: player,
      system: system,
      strength: strength,
      bounty_score: bounty_score
    } = spacecraft

    %{
      "ID" => to_string(id),
      "Player" => [player.external_id],
      "System" => [system.external_id],
      "Last Updated At" => DateTime.to_iso8601(DateTime.utc_now()),
      "Strength" => strength,
      "Bounty Score" => bounty_score
    }
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{
      "ID" => id,
      "Player" => [player_external_id],
      "System" => [system_external_id],
      "System ID" => [system_id]
    } = fields

    %__MODULE__{
      id: id,
      external_id: external_id,
      player: {:unfetched, Trekmap.Galaxy.Player, player_external_id},
      system: {:unfetched, Trekmap.Galaxy.System, system_external_id, system_id},
      strength: Map.get(fields, "Strength"),
      bounty_score: Map.get(fields, "Bounty Score")
    }
  end

  def calculate_bounty_score(resources) do
    Enum.reduce(resources, 0, fn {id, value}, bounty_score ->
      id = String.to_integer(id)

      {_name, score} = Trekmap.Products.get_resource_name_and_value_score(id)
      bounty_score + value * score
    end)
  end
end
