defmodule Trekmap.Products do
  alias Trekmap.{APIClient, Session}
  require Logger

  @buy_resources_endpoint "https://live-193-web.startrek.digitgaming.com/resources/buy_resources"

  # @ship_partials [
  #   {:geological, 3, 3_904_185_676}
  # ]

  @refined_resources [
    {"Parsteel", 1, :raw, 2_325_683_920},
    {"Thritanium", 1, :raw, 743_985_951},
    {"Dlithium", 1, :raw, 2_614_028_847},
    {"Gas ***", 3, :unusual, 2_599_869_530},
    {"Crystal ***", 3, :unusual, 2_367_328_925},
    {"Raw Gas **", 2, :raw, 96_209_859},
    {"Raw Gas ***", 3, :raw, 1_779_416_627},
    {"Raw Ore **", 2, :raw, 1_908_242_242},
    {"Raw Ore ***", 3, :raw, 84_292_608},
    {"Raw Crystal **", 2, :raw, 1_371_898_528},
    {"Raw Crystal ***", 3, :raw, 680_796_905}
  ]

  for {name, level, _type, id} <- @refined_resources do
    def get_resource_name_and_value_score(unquote(id)), do: {unquote(name), unquote(level)}
  end

  def get_resource_name_and_value_score(_other), do: {"Unknown", 1}

  def resource_name(2_325_683_920), do: "parsteel"
  def resource_name(743_985_951), do: "thritanium"
  def resource_name(2_614_028_847), do: "dlithium"

  def buy_resources(resource_id, _amount \\ 1, session) do
    Logger.info("Purchasing additional repair token ID #{resource_id}")

    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "resource_dicts" => [%{"resource_id" => resource_id, "amount" => 1}]
      })

    APIClient.protobuf_request(:post, @buy_resources_endpoint, additional_headers, body)
  end
end
