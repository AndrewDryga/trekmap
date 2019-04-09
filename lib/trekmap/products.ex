defmodule Trekmap.Products do
  alias Trekmap.{APIClient, Session}
  require Logger

  @buy_resources_endpoint "https://live-193-web.startrek.digitgaming.com/resources/buy_resources"

  # @ship_partials [
  #   {:geological, 3, 3_904_185_676}
  # ]

  @refined_resources [
    {"Parsteel", 0.5, :raw, 2_325_683_920},
    {"Thritanium", 0.5, :raw, 743_985_951},
    {"Dlithium", 0.5, :raw, 2_614_028_847},
    {"Gas ***", 3, :unusual, 2_599_869_530},
    {"Crystal ***", 3, :unusual, 2_367_328_925},
    {"Raw Gas **", 2, :raw, 96_209_859},
    {"Raw Gas ***", 3, :raw, 1_779_416_627},
    {"Raw Ore **", 2, :raw, 1_908_242_242},
    {"Raw Ore ***", 4, :raw, 84_292_608},
    {"Raw Crystal **", 2, :raw, 1_371_898_528},
    {"Raw Crystal ***", 4, :raw, 680_796_905}
  ]

  for {name, level, _type, id} <- @refined_resources do
    score = :math.pow(level, 4)
    def get_resource_name_and_value_score(unquote(id)), do: {unquote(name), unquote(score)}
  end

  def get_resource_name_and_value_score(_other), do: {"Unknown", 1}

  def resource_name(2_325_683_920), do: "parsteel"
  def resource_name(743_985_951), do: "thritanium"
  def resource_name(2_614_028_847), do: "dlithium"

  def get_shield_token(1, :hour), do: {3_788_095_604, 60}

  def buy_resources(resource_id, amount \\ 1, session) do
    Logger.info("Purchasing additional repair token ID #{resource_id}")

    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "resource_dicts" => [%{"resource_id" => resource_id, "amount" => amount}]
      })

    APIClient.json_request(:post, @buy_resources_endpoint, additional_headers, body)
  end
end
