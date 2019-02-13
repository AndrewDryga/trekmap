defmodule Trekmap.Galaxy.Alliances.Alliance do
  @behaviour Trekmap.AirDB

  defstruct id: nil, external_id: nil, name: nil, tag: nil

  def table_name, do: "Alliances"

  def struct_to_record(%__MODULE__{} = alliance) do
    %{id: id, tag: tag, name: name} = alliance
    %{"ID" => to_string(id), "Name" => name, "Tag" => tag}
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{"ID" => id, "Name" => name, "Tag" => tag} = fields
    %__MODULE__{id: id, external_id: external_id, name: name, tag: tag}
  end
end
