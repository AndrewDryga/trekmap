defmodule Trekmap.Session do
  alias Trekmap.APIClient

  @accounts_endpoint "https://nv3-live.startrek.digitgaming.com/accounts/v1"
  @sessions_endpoint "#{@accounts_endpoint}/sessions"

  defstruct account_id: nil, master_session_id: nil, session_instance_id: nil

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
    %{"session_id" => master_session_id} = Jason.decode!(body)
    %__MODULE__{master_session_id: master_session_id, account_id: account_id}
  end

  def start_session_instance(%__MODULE__{} = session) do
    url = "#{@sessions_endpoint}/#{session.master_session_id}/instances"
    body = {:form, [account_id: session.account_id]}
    {:ok, body} = APIClient.request(:post, url, additional_headers(), body)
    %{"instance_session_id" => instance_session_id} = Jason.decode!(body)
    %{session | session_instance_id: instance_session_id}
  end

  def session_instance_valid?(%__MODULE__{
        master_session_id: master_session_id,
        session_instance_id: session_instance_id
      })
      when not is_nil(session_instance_id) do
    url = "#{@sessions_endpoint}/#{master_session_id}/instances/#{session_instance_id}"
    body = {:form, []}

    case APIClient.request(:post, url, additional_headers(), body) do
      {:ok, _body} -> true
      _other -> false
    end
  end

  defp additional_headers do
    api_key =
      Application.fetch_env!(:trekmap, __MODULE__)
      |> Keyword.fetch!(:api_key)

    [{"Accept", "*/*"}, {"X-Api-Key", api_key}]
  end

  def session_headers(%__MODULE__{} = session) do
    [{"X-AUTH-SESSION-ID", session.session_instance_id}]
  end
end
