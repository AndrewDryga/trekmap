defmodule Trekmap.Base do
  use Bitwise

  @scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/quick_multi_scan"
  @base_scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/scan_starbase_detailed"
  @translation_endpoint "https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime"
  @alliances_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/get_alliances_public_info"
  @account_id "e4a655634c674cc9aff1b6b7c6c0521a"

  defstruct player_base_id: nil,
            system_id: nil,
            system_tid: nil,
            system_name: nil,
            system_level: nil,
            planet_id: nil,
            planet_name: nil,
            alliance_id: nil,
            alliance_name: nil,
            alliance_tag: nil,
            level: nil,
            name: nil,
            shield_expires_at: nil,
            parsteel: nil,
            thritanium: nil,
            dlithium: nil

  def enrich_bases_information(bases, session) do
    bases
    |> enrich_scan_info(session)
    |> enrich_object_names()
    |> enrich_alliance_names(session)
    |> scan_for_resources(session)
  end

  defp enrich_scan_info(bases, session) do
    target_ids = Enum.map(bases, & &1.player_base_id)

    case scan_targets(target_ids, session) do
      %{} = scan_results ->
        bases
        |> Enum.map(fn base ->
          %{
            "attributes" => %{
              "owner_alliance_id" => alliance_id,
              "owner_level" => level,
              "owner_name" => name,
              "player_shield" => shield
            }
          } = Map.get(scan_results, base.player_base_id)

          shield_expires_at =
            case shield do
              %{"expiry_time" => shield_expires_at} -> shield_expires_at
              _other -> nil
            end

          %{
            base
            | alliance_id: alliance_id,
              level: level,
              name: name,
              shield_expires_at: shield_expires_at
          }
        end)

      :error ->
        bases
    end
  end

  defp scan_targets(target_ids, session) do
    payload =
      Jason.encode!(%{
        "target_ids" => target_ids,
        "fleet_id" => -1,
        "user_id" => @account_id,
        "target_type" => 1
      })

    {:ok, 200, _headers, body} =
      :hackney.request(:post, @scanning_endpoint, headers(session), payload, [:with_body])

    body = Trekmap.raw_binary_to_string(body)

    if String.contains?(body, "user_authentication") do
      raise "Session expired"
    end

    case Trekmap.protobuf_to_json(body) do
      %{"quick_scan_results" => scan_results} -> scan_results
      _else -> :error
    end
  end

  defp get_object_names(object_ids) do
    object_ids_string = object_ids |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.join(",")

    url = "#{@translation_endpoint}?language=en&entity=#{object_ids_string}"

    {:ok, 200, _headers, body} = :hackney.request(:get, url, [], "", [:with_body])
    %{"translations" => %{"entity" => entities}} = Jason.decode!(body)

    for entity <- entities, into: %{} do
      {Map.fetch!(entity, "id"), Map.fetch!(entity, "text")}
    end
  end

  defp enrich_object_names(bases) do
    object_ids = Enum.map(bases, & &1.system_id) ++ Enum.map(bases, & &1.planet_id)
    object_names = get_object_names(object_ids)

    Enum.map(bases, fn base ->
      system_name = Map.get(object_names, to_string(base.system_id))
      planet_name = Map.get(object_names, to_string(base.planet_id))

      %{base | system_name: system_name, planet_name: planet_name}
    end)
  end

  def enrich_alliance_names(bases, session) do
    alliance_ids = Enum.map(bases, & &1.alliance_id)

    payload =
      Jason.encode!(%{
        "alliance_id" => 0,
        "alliance_ids" => alliance_ids
      })

    case :hackney.request(:post, @alliances_endpoint, headers(session), payload, [:with_body]) do
      {:ok, 200, _headers, body} ->
        body = Trekmap.raw_binary_to_string(body)

        if String.contains?(body, "user_authentication") do
          raise "Session expired"
        end

        case Trekmap.protobuf_to_json(body) do
          %{"alliances_info" => alliances} ->
            Enum.map(bases, fn base ->
              case Map.get(alliances, to_string(base.alliance_id)) do
                %{"name" => name, "tag" => tag} ->
                  %{base | alliance_name: name, alliance_tag: tag}

                _other ->
                  base
              end
            end)

          _other ->
            bases
        end

      _other ->
        IO.puts("Can't fetch alliances")
        bases
    end
  end

  def scan_for_resources(bases, session) do
    Enum.map(bases, fn base ->
      payload =
        Jason.encode!(%{
          "fleet_id" => -1,
          "target_user_id" => base.player_base_id
        })

      url = @base_scanning_endpoint

      case :hackney.request(:post, url, headers(session), payload, [:with_body]) do
        {:ok, 200, _headers, body} ->
          case Trekmap.Base.DetailedScan.decode(body) do
            %{result: %{information: %{properties: %{resources: resources}}}} ->
              resources =
                resources
                |> Enum.map(fn resource ->
                  {resource_name(resource.id), resource.amount}
                end)
                |> Enum.into(%{})

              %{
                base
                | parsteel: Map.get(resources, "parsteel"),
                  thritanium: Map.get(resources, "thritanium"),
                  dlithium: Map.get(resources, "dlithium")
              }

            other ->
              IO.puts("Can't resolve rss struct: #{inspect(other)}")
              base
          end

        other ->
          IO.puts("Can't fetch rss struct: #{inspect(other)}")
          base
      end
    end)
  end

  def resource_name(2_325_683_920), do: "parsteel"
  def resource_name(743_985_951), do: "thritanium"
  def resource_name(2_614_028_847), do: "dlithium"

  defp headers(session) do
    Trekmap.request_headers() ++
      [
        {"Accept", "application/x-protobuf"},
        {"Content-Type", "application/x-protobuf"},
        {"X-AUTH-SESSION-ID", session.session_instance_id}
      ]
  end
end
