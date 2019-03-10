defmodule Trekmap.Discord do
  alias Trekmap.APIClient

  @webhook_endpoint "https://discordapp.com/api/webhooks/554215988107673622/HweNpj3MwnrCwLDDbGRajyOcq_F9Z_rwV1i_XIJIdnRhyU2WIO3607NsOGseT-M4-ztM"

  def send_message(body) do
    additional_headers = [{"content-type", "application/json"}]
    body = Jason.encode!(%{"content" => body})
    APIClient.request(:post, @webhook_endpoint, additional_headers, body)
  end
end
