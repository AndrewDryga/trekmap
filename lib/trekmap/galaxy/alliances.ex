defmodule Trekmap.Galaxy.Alliances do
  alias Trekmap.{APIClient, Session, AirDB}
  alias Trekmap.Galaxy.Alliances.Alliance

  @alliances_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/get_alliances_public_info"

  def list_alliances_by_ids(alliance_ids, %Session{} = session) do
    body =
      Jason.encode!(%{
        "alliance_id" => 0,
        "alliance_ids" => alliance_ids
      })

    additional_headers = Session.session_headers(session)

    with {:ok, %{response: %{"alliances_info" => alliances_info}}} <-
           APIClient.protobuf_request(:post, @alliances_endpoint, additional_headers, body) do
      alliances =
        for alliance_id <- alliance_ids, into: %{} do
          case Map.fetch!(alliances_info, to_string(alliance_id)) do
            nil ->
              {alliance_id, nil}

            %{"name" => name, "tag" => tag} ->
              {alliance_id, %Alliance{id: alliance_id, name: name, tag: tag}}
          end
        end

      {:ok, alliances}
    end
  end

  def list_allies do
    query_params = %{
      "maxRecords" => 100,
      "filterByFormula" => "OR({Relation} = 'Ally', {Relation} = 'NAP')"
    }

    with {:ok, [struct]} <- AirDB.list(Alliance, query_params) do
      {:ok, struct}
    else
      {:ok, []} -> {:error, :not_found}
      other -> other
    end
  end

  def list_enemies do
    query_params = %{
      "maxRecords" => 100,
      "filterByFormula" => "OR({Relation} = 'Enemy')"
    }

    AirDB.list(Alliance, query_params)
  end
end
