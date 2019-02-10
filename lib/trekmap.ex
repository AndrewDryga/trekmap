defmodule Trekmap do
  def scan do
    session =
      Trekmap.Session.start_session()
      |> Trekmap.Session.start_session_instance()

    file = File.stream!("bases.csv")

    Trekmap.System.list_systems(session)
    |> Task.async_stream(
      fn system ->
        IO.puts("Scanning #{system.name} (#{system.id}) ##{inspect(system.trans_id)}..")

        Trekmap.System.list_bases(system, session)
        |> Trekmap.Base.enrich_bases_information(session)
      end,
      max_concurrency: 20,
      timeout: 120_000
    )
    |> Stream.flat_map(fn {:ok, bases} ->
      Enum.map(bases, fn base ->
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
    end)
    |> NimbleCSV.RFC4180.dump_to_stream()
    |> Stream.into(file)
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

  def protobuf_to_json(body) do
    body
    |> String.replace(~r/^[^{]*/, "")
    |> String.replace(~r/}\*.*$/, "}")
    |> case do
      "" ->
        %{}

      binary ->
        case Jason.decode(binary) do
          {:ok, map} ->
            map

          _other ->
            IO.warn("failed to decode: #{inspect(binary)}")
            %{}
        end
    end
  end

  def raw_binary_to_string(raw) do
    codepoints = String.codepoints(raw)

    Enum.reduce(codepoints, fn w, result ->
      cond do
        String.valid?(w) ->
          result <> w

        true ->
          result
      end
    end)
  end
end
