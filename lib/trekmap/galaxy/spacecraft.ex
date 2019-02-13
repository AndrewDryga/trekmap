defmodule Trekmap.Galaxy.Spacecraft do
  @behaviour Trekmap.AirDB

  defstruct external_id: nil,
            system: nil,
            player: nil,
            id: nil

  def table_name, do: "Spacecrafts"

  def struct_to_record(%__MODULE__{} = system) do
    %{id: id, player: player, system: system} = system

    %{
      "ID" => to_string(id),
      "Player" => [player.external_id],
      "System" => [system.external_id],
      "Last Updated At" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{
      "ID" => id,
      "Player" => [player_external_id],
      "System" => [system_external_id]
    } = fields

    %__MODULE__{
      id: id,
      external_id: external_id,
      player: {:unfetched, Trekmap.Galaxy.Player, player_external_id},
      system: {:unfetched, Trekmap.Galaxy.System, system_external_id}
    }
  end
end
