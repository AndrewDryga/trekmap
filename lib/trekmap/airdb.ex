defmodule Trekmap.AirDB do
  require Logger

  @callback table_name() :: String.t()
  @callback record_to_struct(map()) :: map()
  @callback struct_to_record(map()) :: map()

  @cache_opts [ttl: :timer.minutes(120)]

  @hackney_opts [
    :with_body,
    recv_timeout: 30_000,
    connect_timeout: 15_000
  ]

  def list(struct, query_params \\ %{}) when is_atom(struct) do
    with {:ok, %{"records" => records}} <- get(struct.table_name(), query_params) do
      {:ok, Enum.map(records, &struct.record_to_struct/1)}
    end
  end

  def create_or_update(struct) when is_map(struct) do
    struct_module = struct.__struct__
    table_name = struct_module.table_name()

    attrs = struct_module.struct_to_record(struct)

    with {:ok, fetched} <- fetch_by_id(struct_module, struct.id) do
      if structs_equal?(struct, fetched) do
        {:ok, fetched}
      else
        with {:ok, record} <- update(table_name, fetched.external_id, attrs) do
          fetched = struct_module.record_to_struct(record)
          Cachex.put(:airdb_cache, {struct_module, fetched.id}, fetched, @cache_opts)
          {:ok, fetched}
        end
      end
    else
      {:error, :not_found} ->
        with {:ok, record} <- create(table_name, attrs) do
          struct = struct_module.record_to_struct(record)
          {:ok, _ttl} = Cachex.put(:airdb_cache, {struct_module, struct.id}, struct, @cache_opts)
          {:ok, struct}
        end

      other ->
        other
    end
  end

  defp structs_equal?(local, remote) do
    local
    |> Map.from_struct()
    |> Enum.all?(fn {key, value} ->
      if is_nil(value) do
        true
      else
        Map.fetch!(remote, key) == value
      end
    end)
  end

  def fetch_by_external_id(struct, id) when is_atom(struct) do
    table_name = "#{struct.table_name()}/#{id}"

    with {:ok, record} <- get(table_name) do
      {:ok, struct.record_to_struct(record)}
    end
  end

  def fetch_by_id(struct, id) when is_atom(struct) do
    with {:ok, %{} = struct} <- Cachex.get(:airdb_cache, {struct, id}) do
      {:ok, struct}
    else
      _other ->
        query_params = %{"maxRecords" => 1, "filterByFormula" => "{ID} = '#{id}'"}

        with {:ok, [struct]} <- list(struct, query_params) do
          {:ok, _ttl} = Cachex.put(:airdb_cache, {struct, id}, struct, @cache_opts)
          {:ok, struct}
        else
          {:ok, []} -> {:error, :not_found}
          other -> other
        end
    end
  end

  def preload(struct, field_or_fields) do
    field_or_fields
    |> List.wrap()
    |> Enum.reduce(struct, fn field, struct ->
      case Map.fetch!(struct, field) do
        {:unfetched, schema, external_id, _id} ->
          {:ok, value} = fetch_by_external_id(schema, external_id)
          Map.put(struct, field, value)

        {:unfetched, schema, external_id} ->
          {:ok, value} = fetch_by_external_id(schema, external_id)
          Map.put(struct, field, value)

        _value ->
          struct
      end
    end)
  end

  defp get(table, query_params \\ %{}) do
    config = config()
    endpoint = Keyword.fetch!(config, :endpoint)
    base_id = Keyword.fetch!(config, :base_id)
    api_key = Keyword.fetch!(config, :api_key)

    url = "#{endpoint}/#{base_id}/#{table}?#{URI.encode_query(query_params)}"
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

    with {:ok, 200, _headers, body} <-
           :hackney.request(:get, url, headers, "", @hackney_opts) do
      {:ok, Jason.decode!(body)}
    else
      {:ok, 429, _headers, _body} ->
        Logger.warn("[Airdb] Rate limited, waiting 30 seconds")
        :timer.sleep(32_000)
        get(table, query_params)

      other ->
        other
    end
  end

  defp create(table, attrs) do
    config = config()
    endpoint = Keyword.fetch!(config, :endpoint)
    base_id = Keyword.fetch!(config, :base_id)
    api_key = Keyword.fetch!(config, :api_key)

    url = "#{endpoint}/#{base_id}/#{table}"
    body = Jason.encode!(%{"fields" => attrs})
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

    with {:ok, 200, _headers, body} <-
           :hackney.request(:post, url, headers, body, @hackney_opts) do
      {:ok, Jason.decode!(body)}
    else
      {:ok, 429, _headers, _body} ->
        Logger.warn("[Airdb] Rate limited, waiting 30 seconds")
        :timer.sleep(33_000)
        create(table, attrs)

      other ->
        other
    end
  end

  defp update(table, id, attrs) do
    config = config()
    endpoint = Keyword.fetch!(config, :endpoint)
    base_id = Keyword.fetch!(config, :base_id)
    api_key = Keyword.fetch!(config, :api_key)

    url = "#{endpoint}/#{base_id}/#{table}/#{id}"
    body = Jason.encode!(%{"fields" => attrs})
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

    with {:ok, 200, _headers, body} <-
           :hackney.request(:patch, url, headers, body, @hackney_opts) do
      {:ok, Jason.decode!(body)}
    else
      {:ok, 429, _headers, _body} ->
        Logger.warn("[Airdb] Rate limited, waiting 30 seconds")
        :timer.sleep(31_000)
        update(table, id, attrs)

      other ->
        other
    end
  end

  defp config do
    Application.fetch_env!(:trekmap, __MODULE__)
  end
end
