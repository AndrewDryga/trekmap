defmodule Trekmap.Discord do
  alias Trekmap.APIClient

  @hive_log_endpoint "https://discordapp.com/api/webhooks/566593319203766274/UC_jHCFJWtMMS3DCT4l69S8EPeVh1b-GjeO9uzDThxVQx95NtOg_P-TGmUXODMoWaZ9d"
  @kill_log_endpoint "https://discordapp.com/api/webhooks/566593069462454292/xqkXjV2Sssa-WcrnwNCTg2ev7iH_pa-iGdvhUz5jbL8re-OWVXqAthzTVlIOkIzKjuFc"
  @general_endpoint "https://discordapp.com/api/webhooks/566593456269426698/n-STb1jSKJDuM-CKQdjLcUCWDSlm_-yUysM76m7Pfi5adpgHtSnVmoNef1XMwEoAuNU5"

  def send_message(body, endpoint \\ @general_endpoint) do
    additional_headers = [{"content-type", "application/json"}]
    body = Jason.encode!(%{"content" => body})
    APIClient.request(:post, endpoint, additional_headers, body)
  end

  def log_hive_change(body) do
    send_message(body, @hive_log_endpoint)
  end

  def log_kill(body) do
    send_message(body, @kill_log_endpoint)
  end
end
