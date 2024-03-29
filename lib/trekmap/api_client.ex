defmodule Trekmap.APIClient do
  require Logger

  @decoder Trekmap.APIClient.JsonResponse

  @hackney_opts [
    :with_body,
    recv_timeout: 20_000,
    connect_timeout: 10_000
  ]

  def request(method, endpoint, additional_headers, body) do
    headers = request_headers() ++ additional_headers

    with {:ok, 200, _headers, body} <-
           :hackney.request(method, endpoint, headers, body, @hackney_opts) do
      {:ok, body}
    else
      {:error, :timeout} ->
        Logger.warn("Request timed out, #{inspect({method, endpoint, body})}. Retrying in 2s")
        :timer.sleep(2_000)
        request(method, endpoint, additional_headers, body)

      other ->
        other
    end
  end

  def json_request(method, endpoint, additional_headers, body) do
    headers =
      [
        {"Accept", "application/json"},
        {"Content-Type", "application/json"}
      ] ++
        additional_headers

    with {:ok, body} when body != "" <- request(method, endpoint, headers, body),
         {:ok, response} <- Jason.decode(body) do
      {:ok, response}
    else
      {:error, %Jason.DecodeError{data: data}} ->
        decode_protobuf_response(data, @decoder)
        |> maybe_decode_json()
        |> case do
          {:ok, %{response: %{} = response}} -> {:error, response}
          {:ok, map} -> {:error, map}
          :ok -> :error
          {:error, reason} -> {:error, reason}
        end

      {:ok, ""} ->
        :ok

      {:ok, 500, _headers, "{" <> _ = body} ->
        Jason.decode(body)
        |> case do
          {:ok, response} -> {:error, response}
          {:error, reason} -> {:error, reason}
        end

      {:ok, 500, _headers, body} ->
        decode_protobuf_response(body, @decoder)
        |> maybe_decode_json()
        |> case do
          {:ok, %{response: %{} = response}} -> {:error, response}
          {:ok, map} -> {:error, map}
          :ok -> :error
          {:error, reason} -> {:error, reason}
        end

      other ->
        other
    end
  end

  def protobuf_request(method, endpoint, additional_headers, body, decode_struct \\ @decoder) do
    headers =
      [
        {"Accept", "application/x-protobuf"},
        {"Content-Type", "application/x-protobuf"}
      ] ++
        additional_headers

    with {:ok, body} <- request(method, endpoint, headers, body) do
      try do
        decode_protobuf_response(body, decode_struct)
        |> maybe_decode_json()
      rescue
        # Sometimes API returns response in format we can't read, requesting it again solves
        # the issue
        Protobuf.DecodeError ->
          :timer.sleep(500)
          Logger.error("Retrying request..")
          protobuf_request(method, endpoint, additional_headers, body, decode_struct)
      end
    else
      {:ok, 500, _headers, body} ->
        decode_protobuf_response(body, @decoder)
        |> maybe_decode_json()
        |> case do
          {:ok, %{response: %{} = response}} -> {:error, response}
          {:ok, map} -> {:error, map}
          :ok -> :error
          {:error, reason} -> {:error, reason}
        end

      other ->
        other
    end
  end

  def decode_protobuf_response(binary, struct) do
    case struct.decode(binary) do
      %{response: response} = map when is_map(response) ->
        {:ok, map}

      %{error: error} when not is_nil(error) ->
        {:error, error}

      {:error, %{error: %{body: "user_authentication", type: 102}}} ->
        {:error, :session_expired}

      %{error: nil, response: nil} ->
        :ok
    end
  end

  defp maybe_decode_json({:ok, %{response: %{type: 42, body: json_body}} = response}) do
    {:ok, %{response | response: Jason.decode!(json_body)}}
  end

  defp maybe_decode_json(other) do
    other
  end

  defp request_headers do
    [
      {"X-Unity-Version", "5.6.4p3"},
      {"X-PRIME-VERSION", "0.543.9442"},
      {"X-Suppress-Codes", "1"},
      {"X-PRIME-SYNC", "0"},
      {"Accept-Language", "en"},
      {"X-TRANSACTION-ID", UUID.uuid4()},
      {"User-Agent", "startrek/0.543.9378 CFNetwork/976 Darwin/18.2.0"}
    ]
  end
end
