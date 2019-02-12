defmodule Trekmap.Products do
  alias Trekmap.{APIClient, Session}
  require Logger

  @buy_resources_endpoint "https://live-193-web.startrek.digitgaming.com/resources/buy_resources"

  @ship_partials [
    {:geological, 3, 3_904_185_676}
  ]

  @refined_resources [
    {:gas, 3, :unusual, 2_599_869_530},
    {:crystal, 3, :unusual, 2_367_328_925}
  ]

  def resource_name(2_325_683_920), do: "parsteel"
  def resource_name(743_985_951), do: "thritanium"
  def resource_name(2_614_028_847), do: "dlithium"

  def buy_resources(resource_id, amount \\ 1, session) do
    Logger.info("Purchasing additional repair token ID #{resource_id}")

    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "resource_dicts" => [%{"resource_id" => resource_id, "amount" => 1}]
      })

    APIClient.protobuf_request(:post, @buy_resources_endpoint, additional_headers, body)
  end
end
