defmodule Trekmap.Me.Rewards do
  # alias Trekmap.{APIClient, Session}
  #
  # @rewards_list_endpoint "https://nv3-live.startrek.digitgaming.com/content/v1/products/prime/event/tournament/193/"
  #
  # def open_all_chests(%Session{} = session) do
  #   {:ok, refinery_chests} = list_available_refinery_chests(session)
  #   {:ok, bonus_chests} = list_available_bonus_chests(session)
  #   {:ok, first_time_alliance_chests} = list_available_first_time_alliance_chests(session)
  #   {:ok, alliance_chests_to_purchase} = list_alliance_chests_to_purchase(session)
  #   {:ok, available_officer_chests} = list_available_officer_chests(session)
  #   {:ok, resource_chests_to_purchase} = list_resource_chests_to_purchase(session)
  #
  #   (refinery_chests ++
  #      bonus_chests ++
  #      first_time_alliance_chests ++
  #      alliance_chests_to_purchase ++
  #      available_officer_chests ++
  #      resource_chests_to_purchase)
  #   |> Enum.map(fn chest ->
  #     %{"bundle_id" => bundle_id, "cost" => cost_options} = chest
  #
  #     %{"quantity" => quantity} =
  #       Enum.max_by(cost_options, fn %{"quantity" => quantity} -> quantity end)
  #
  #     {bundle_id, quantity}
  #   end)
  #   |> Enum.each(fn {bundle_id, quantity} -> :ok = open_chest(bundle_id, quantity, session) end)
  # end
  #
  # def list_available_rewards(%Session{} = session) do
  #   additional_headers =
  #     Session.additional_headers() ++
  #       [
  #         {"X-AUTH-SESSION-ID", session.master_session_id}
  #       ]
  #
  #   endpoint = "#{@rewards_list_endpoint}/#{session.account_id}?category=0"
  #
  #   with {:ok, response} <-
  #          APIClient.request(
  #            :get,
  #            endpoint,
  #            additional_headers,
  #            ""
  #          ) do
  #     %{"bundles" => bundles} = Jason.decode!(response)
  #
  #     {:ok, bundles}
  #   end
  # end

  # def open_chest(chest_id, quantity, %Session{} = session) do
  #   additional_headers =
  #     Session.additional_headers() ++
  #       [
  #         {"X-AUTH-SESSION-ID", session.master_session_id}
  #       ]
  #
  #   endpoint = "#{@account_payments_endpoint}/#{session.account_id}/chests/orders"
  #
  #   payload =
  #     {:form,
  #      [
  #        {"master_session_id", session.master_session_id},
  #        {"chest_id", chest_id},
  #        {"quantity", quantity},
  #        {"options", ""}
  #      ]}
  #
  #   with {:ok, response} <- APIClient.request(:post, endpoint, additional_headers, payload) do
  #     IO.inspect(response, label: "WOOO")
  #     :ok
  #   end
  # end
end
