defmodule Trekmap.Session do
  @accounts_endpoint "https://nv3-live.startrek.digitgaming.com/accounts/v1"
  @account_id "e4a655634c674cc9aff1b6b7c6c0521a"

  @api_key "FCX2QsbxHjSP52B"

  @username "dgt1g148301fcf1a46188c38c26dfc48f9dc"
  @password "dgt1e8d857a5e1cb4cc6a72b3ec0cd8da9d9"

  defstruct account_id: @account_id, session_id: nil, session_instance_id: nil

  def start_session do
    url = "#{@accounts_endpoint}/sessions"

    payload =
      {:form,
       [
         method: "apple",
         username: @username,
         password: @password,
         partner_tracking_name: "scopely_device_token",
         partner_tracking_id: "b58b1939-f752-4660-a4fe-807f863d7427",
         product_code: "prime",
         channel: "digit_IPhonePlayer"
       ]}

    {:ok, _code, _headers, body} = :hackney.request(:post, url, headers(), payload, [:with_body])
    %{"session_id" => session_id} = Jason.decode!(body)
    %__MODULE__{session_id: session_id}
  end

  def start_session_instance(%__MODULE__{} = session) do
    url = "#{@accounts_endpoint}/sessions/#{session.session_id}/instances"
    payload = {:form, [account_id: @account_id]}
    {:ok, 200, _headers, body} = :hackney.request(:post, url, headers(), payload, [:with_body])
    %{"instance_session_id" => instance_session_id} = Jason.decode!(body)
    %{session | session_instance_id: instance_session_id}
  end

  def session_instance_valid?(%__MODULE__{
        session_id: session_id,
        session_instance_id: session_instance_id
      })
      when not is_nil(session_instance_id) do
    url = "#{@accounts_endpoint}/sessions/#{session_id}/instances/#{session_instance_id}"
    payload = {:form, []}

    case :hackney.request(:post, url, headers(), payload, [:with_body]) do
      {:ok, 200, _headers, _body} -> true
      _other -> false
    end
  end

  defp headers do
    Trekmap.request_headers() ++ [{"Accept", "*/*"}, {"X-Api-Key", @api_key}]
  end
end
