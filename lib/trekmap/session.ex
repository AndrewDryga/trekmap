defmodule Trekmap.Session do
  alias Trekmap.APIClient

  @accounts_endpoint "https://nv3-live.startrek.digitgaming.com/accounts/v1"
  @sessions_endpoint "#{@accounts_endpoint}/sessions"
  @check_account_endpoint "https://live-193-web.startrek.digitgaming.com/check_account"

  defstruct account_id: nil,
            master_account_id: nil,
            master_session_id: nil,
            session_instance_id: nil,
            fleet_id: nil,
            home_system_id: nil,
            # [604_074_052, 719_474_967],
            hive_system_ids: [2_136_091_294],
            galaxy: Graph.new(),
            game_config: %{}

  def start_session do
    config = Application.fetch_env!(:trekmap, __MODULE__)
    username = Keyword.fetch!(config, :username)
    password = Keyword.fetch!(config, :password)
    account_id = Keyword.fetch!(config, :account_id)

    body =
      {:form,
       [
         method: "apple",
         username: username,
         password: password,
         partner_tracking_name: "scopely_device_token",
         partner_tracking_id: "b58b1939-f752-4660-a4fe-807f863d7427",
         product_code: "prime",
         channel: "digit_IPhonePlayer"
       ]}

    {:ok, body} = APIClient.request(:post, @sessions_endpoint, additional_headers(), body)
    %{"session_id" => master_session_id, "master_id" => master_account_id} = Jason.decode!(body)

    {:ok,
     %__MODULE__{
       master_session_id: master_session_id,
       master_account_id: master_account_id,
       account_id: account_id
     }}
  end

  def start_session_instance(%__MODULE__{} = session) do
    url = "#{@sessions_endpoint}/#{session.master_session_id}/instances"
    body = {:form, [account_id: session.account_id]}

    with {:ok, body} <- APIClient.request(:post, url, additional_headers(), body) do
      case Jason.decode!(body) do
        %{"instance_session_id" => instance_session_id} ->
          {:ok, %{session | session_instance_id: instance_session_id}}

        %{"code" => 42, "http_code" => 400} ->
          {:error, :retry_later}

        %{"msg" => "Instance is in maintenance"} ->
          {:error, :retry_later}
      end
    end
  end

  def session_instance_valid?(%__MODULE__{} = session) do
    additional_headers = session_headers(session)

    case APIClient.json_request(:post, @check_account_endpoint, additional_headers, "") do
      {:ok, %{"consistency_state" => %{}}} -> true
      _other -> false
    end
  end

  def additional_headers do
    api_key =
      Application.fetch_env!(:trekmap, __MODULE__)
      |> Keyword.fetch!(:api_key)

    [{"Accept", "*/*"}, {"X-Api-Key", api_key}]
  end

  def session_headers(%__MODULE__{session_instance_id: session_instance_id})
      when not is_nil(session_instance_id) do
    [{"X-AUTH-SESSION-ID", session_instance_id}]
  end
end
