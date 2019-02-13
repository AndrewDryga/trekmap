defmodule Trekmap.Galaxy.System.Planet do
  @behaviour Trekmap.AirDB

  defstruct id: nil, external_id: nil, system_external_id: nil, name: nil

  def table_name, do: "Planets"

  def struct_to_record(%__MODULE__{} = planet) do
    %{
      id: id,
      name: name,
      system_external_id: system_external_id
    } = planet

    %{"ID" => id, "Name" => name, "System" => [system_external_id]}
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{"ID" => id, "Name" => name, "System" => [system_external_id]} = fields

    %__MODULE__{
      id: id,
      name: name,
      external_id: external_id,
      system_external_id: system_external_id
    }
  end
end
