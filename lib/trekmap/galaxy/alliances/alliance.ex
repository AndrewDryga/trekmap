defmodule Trekmap.Galaxy.Alliances.Alliance do
  @behaviour Trekmap.AirDB

  defstruct id: nil, external_id: nil, name: nil, tag: nil, other_known_names: []

  def table_name, do: "Alliances"

  def struct_to_record(%__MODULE__{} = alliance) do
    %{id: id, tag: tag, name: name, other_known_names: other_known_names} = alliance

    %{
      "ID" => to_string(id),
      "Name" => name,
      "Tag" => tag,
      "AKA" => Enum.join(Enum.uniq(other_known_names ++ [name]), ",")
    }
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{"ID" => id, "Name" => name, "Tag" => tag} = fields

    other_known_names =
      Map.get(fields, "AKA", "")
      |> String.split(",")
      |> Enum.reject(&(&1 == ""))

    %__MODULE__{
      id: id,
      external_id: external_id,
      name: name,
      tag: tag,
      other_known_names: other_known_names
    }
  end
end
