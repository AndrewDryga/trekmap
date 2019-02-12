defmodule Trekmap.Galaxy.ObjectNames do
  @translation_endpoint "https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime"

  def get_object_names(object_ids) do
    object_ids_string = object_ids |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.join(",")
    url = "#{@translation_endpoint}?language=en&entity=#{object_ids_string}"

    {:ok, 200, _headers, body} = :hackney.request(:get, url, [], "", [:with_body])
    %{"translations" => %{"entity" => entities}} = Jason.decode!(body)

    for entity <- entities, into: %{} do
      {Map.fetch!(entity, "id"), Map.fetch!(entity, "text")}
    end
  end
end
