defmodule Trekmap.Galaxy.Player do
  @behaviour Trekmap.AirDB

  defstruct id: nil,
            external_id: nil,
            level: nil,
            name: nil,
            alliance: nil,
            other_known_names: []

  def table_name, do: "Players"

  def struct_to_record(%__MODULE__{} = player) do
    %{
      id: id,
      level: level,
      name: name,
      alliance: alliance,
      other_known_names: other_known_names
    } = player

    alliance_external_id = if alliance, do: [alliance.external_id], else: []

    %{
      "ID" => to_string(id),
      "Name" => name,
      "Level" => level,
      "Alliance" => alliance_external_id,
      "AKA" => Enum.join(Enum.uniq(other_known_names ++ [name]), ",")
    }
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{
      "ID" => id,
      "Name" => name,
      "Level" => level
    } = fields

    alliance =
      if alliance_external_id = Map.get(fields, "Alliance") do
        [alliance_external_id] = alliance_external_id
        {:unfetched, Trekmap.Galaxy.Alliances.Alliance, alliance_external_id}
      end

    other_known_names =
      Map.get(fields, "AKA", "")
      |> String.split(",")
      |> Enum.reject(&(&1 == ""))

    %__MODULE__{
      id: id,
      external_id: external_id,
      level: level,
      name: name,
      alliance: alliance,
      other_known_names: other_known_names
    }
  end
end
