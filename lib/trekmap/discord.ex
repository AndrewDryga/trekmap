defmodule Trekmap.Discord do
  alias Trekmap.APIClient

  @kill_log_endpoint "https://discordapp.com/api/webhooks/555363993879969792/txGuP6kmu4_WZn951Fi9EZtiRIJwFZ94-cdc9v-cD3dbnSHrSGNShQ4NoUwaXgK5awN5"
  @webhook_endpoint "https://discordapp.com/api/webhooks/554215988107673622/HweNpj3MwnrCwLDDbGRajyOcq_F9Z_rwV1i_XIJIdnRhyU2WIO3607NsOGseT-M4-ztM"

  def send_message(body, endpoint \\ @webhook_endpoint) do
    additional_headers = [{"content-type", "application/json"}]
    body = Jason.encode!(%{"content" => body})
    APIClient.request(:post, @webhook_endpoint, additional_headers, body)
  end

  def log_kill(body) do
    send_message(body, @kill_log_endpoint)
  end
end
