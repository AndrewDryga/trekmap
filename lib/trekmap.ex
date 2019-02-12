defmodule Trekmap do
  def scan do
    {:ok, session} = Trekmap.SessionManager.fetch_session()

    bases_file = File.stream!("bases.csv")
    miners_file = File.stream!("miners.csv")

    {bases, miners} =
      Trekmap.System.list_systems(session)
      |> Task.async_stream(
        fn system ->
          IO.puts("Scanning #{system.name} (#{system.id}) ##{inspect(system.trans_id)}..")

          {bases, miners} = Trekmap.System.list_bases_and_miners(system, session)
          bases = Trekmap.Base.enrich_bases_information(bases, session)
          miners = Trekmap.Ship.enrich_ships_information(miners, session)

          {bases, miners}
        end,
        max_concurrency: 30,
        timeout: 120_000
      )
      |> Enum.reduce({[], []}, fn {:ok, {bases, miners}}, {bases_acc, miners_acc} ->
        {bases ++ bases_acc, miners ++ miners_acc}
      end)

    bases
    |> Stream.map(fn base ->
      [
        base.alliance_tag,
        base.name,
        base.level,
        base.parsteel,
        base.thritanium,
        base.dlithium,
        base.system_name,
        base.system_id,
        base.system_tid,
        base.planet_name,
        base.shield_expires_at
      ]
    end)
    |> NimbleCSV.RFC4180.dump_to_stream()
    |> Stream.into(bases_file)
    |> Stream.run()

    miners
    |> Stream.map(fn miner ->
      [
        miner.alliance_tag,
        miner.name,
        miner.level,
        miner.system_name,
        miner.system_id,
        miner.system_tid
      ]
    end)
    |> NimbleCSV.RFC4180.dump_to_stream()
    |> Stream.into(miners_file)
    |> Stream.run()
  end

  def request_headers do
    [
      {"X-Unity-Version", "5.6.4p3"},
      {"X-PRIME-VERSION", "0.543.8939"},
      {"X-Suppress-Codes", "1"},
      {"X-PRIME-SYNC", "0"},
      {"Accept-Language", "en"},
      {"X-TRANSACTION-ID", UUID.uuid4()},
      {"User-Agent", "startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0"}
    ]
  end

  def get_protobuf_response(binary, struct \\ Trekmap.APIClient.JsonResponse) do
    case struct.decode(binary) do
      %{response: response} = map when is_map(response) ->
        {:ok, map}

      %{error: error} when not is_nil(error) ->
        {:error, error}

      %{error: nil, response: nil} ->
        :ok
    end
  end
end
