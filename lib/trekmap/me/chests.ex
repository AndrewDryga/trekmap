defmodule Trekmap.Me.Chests do
  alias Trekmap.{APIClient, Session}
  require Logger

  @account_payments_endpoint "https://nv3-live.startrek.digitgaming.com/payments/v1/accounts"

  @purchase_from_alliance_store [
    # Relocation token
    1_088_385_569
  ]
  @purchase_from_resources_store [
    # Daily Reward Pack
    1_045_295_611,
    # Daily Choice Reward Pack
    1_511_808_981,
    # Daily Elite Reward Pack
    648_529_260
  ]

  @max_refinery_batch_quantity 2

  def open_all_chests(%Session{} = session) do
    {:ok, refinery_chests} = list_available_refinery_chests(session)
    {:ok, bonus_chests} = list_available_bonus_chests(session)
    {:ok, first_time_alliance_chests} = list_available_first_time_alliance_chests(session)
    {:ok, alliance_chests_to_purchase} = list_alliance_chests_to_purchase(session)
    {:ok, available_officer_chests} = list_available_officer_chests(session)
    {:ok, resource_chests_to_purchase} = list_resource_chests_to_purchase(session)

    (refinery_chests ++
       bonus_chests ++
       first_time_alliance_chests ++
       alliance_chests_to_purchase ++
       available_officer_chests ++
       resource_chests_to_purchase)
    |> Enum.map(fn chest ->
      %{"bundle_id" => bundle_id, "cost" => cost_options} = chest

      %{"quantity" => quantity} =
        Enum.max_by(cost_options, fn %{"quantity" => quantity} -> quantity end)

      {bundle_id, quantity}
    end)
    |> Enum.each(fn {bundle_id, quantity} -> :ok = open_chest(bundle_id, quantity, session) end)
  end

  def list_available_refinery_chests(%Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint =
      "#{@account_payments_endpoint}/#{session.account_id}/bundles/store" <>
        "?master_session_id=#{session.master_session_id}&bundle_type=virtual&category=refining"

    with {:ok, response} <-
           APIClient.request(
             :get,
             endpoint,
             additional_headers,
             ""
           ) do
      %{"bundles" => bundles} = Jason.decode!(response)

      bundles =
        Enum.flat_map(bundles, fn bundle ->
          %{"offer_details" => %{"valid_count" => valid_count}, "cost" => cost} = bundle

          if valid_count > 0 do
            cost =
              Enum.reject(cost, fn %{"quantity" => quantity} ->
                quantity > @max_refinery_batch_quantity
              end)

            [Map.put(bundle, "cost", cost)]
          else
            []
          end
        end)

      {:ok, bundles}
    end
  end

  def list_available_officer_chests(%Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint =
      "#{@account_payments_endpoint}/#{session.account_id}/bundles/store" <>
        "?master_session_id=#{session.master_session_id}&bundle_type=virtual&category=gacha"

    with {:ok, response} <-
           APIClient.request(
             :get,
             endpoint,
             additional_headers,
             ""
           ) do
      %{"bundles" => bundles} = Jason.decode!(response)

      bundles =
        Enum.flat_map(bundles, fn bundle ->
          %{"bundle_id" => bundle_id, "offer_details" => offer_details} = bundle

          valid_count = Map.get(offer_details, "valid_count", 0)

          if valid_count > 0 and bundle_id in @purchase_from_alliance_store do
            [bundle]
          else
            []
          end
        end)

      {:ok, bundles}
    end
  end

  def list_available_bonus_chests(%Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint =
      "#{@account_payments_endpoint}/#{session.account_id}/bundles/store" <>
        "?master_session_id=#{session.master_session_id}&bundle_type=virtual&category=chests"

    with {:ok, response} <-
           APIClient.request(
             :get,
             endpoint,
             additional_headers,
             ""
           ) do
      %{"bundles" => bundles} = Jason.decode!(response)

      bundles =
        Enum.flat_map(bundles, fn bundle ->
          %{"offer_details" => %{"valid_count" => valid_count}} = bundle

          if valid_count > 0 do
            [bundle]
          else
            []
          end
        end)

      {:ok, bundles}
    end
  end

  def list_available_first_time_alliance_chests(%Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint =
      "#{@account_payments_endpoint}/#{session.account_id}/bundles/store" <>
        "?master_session_id=#{session.master_session_id}&bundle_type=virtual&category=first_time_alliance"

    with {:ok, response} <-
           APIClient.request(
             :get,
             endpoint,
             additional_headers,
             ""
           ) do
      %{"bundles" => bundles} = Jason.decode!(response)

      bundles =
        Enum.flat_map(bundles, fn bundle ->
          %{"offer_details" => %{"valid_count" => valid_count}} = bundle

          if valid_count > 0 do
            [bundle]
          else
            []
          end
        end)

      {:ok, bundles}
    end
  end

  def list_alliance_chests_to_purchase(%Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint =
      "#{@account_payments_endpoint}/#{session.account_id}/bundles/store" <>
        "?master_session_id=#{session.master_session_id}&bundle_type=virtual&category=alliances"

    with {:ok, response} <-
           APIClient.request(
             :get,
             endpoint,
             additional_headers,
             ""
           ) do
      %{"bundles" => bundles} = Jason.decode!(response)

      bundles =
        Enum.flat_map(bundles, fn bundle ->
          %{"bundle_id" => bundle_id, "offer_details" => offer_details} = bundle

          valid_count = Map.get(offer_details, "valid_count", 0)

          if valid_count > 0 and bundle_id in @purchase_from_alliance_store do
            [bundle]
          else
            []
          end
        end)

      {:ok, bundles}
    end
  end

  def list_resource_chests_to_purchase(%Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint =
      "#{@account_payments_endpoint}/#{session.account_id}/bundles/store" <>
        "?master_session_id=#{session.master_session_id}&bundle_type=virtual&category=resources"

    with {:ok, response} <-
           APIClient.request(
             :get,
             endpoint,
             additional_headers,
             ""
           ) do
      %{"bundles" => bundles} = Jason.decode!(response)

      bundles =
        Enum.flat_map(bundles, fn bundle ->
          %{"bundle_id" => bundle_id, "offer_details" => offer_details} = bundle

          valid_count = Map.get(offer_details, "valid_count", 0)

          if valid_count > 0 and bundle_id in @purchase_from_resources_store do
            [bundle]
          else
            []
          end
        end)

      {:ok, bundles}
    end
  end

  def open_chest(chest_id, quantity, %Session{} = session) do
    additional_headers =
      Session.additional_headers() ++
        [
          {"X-AUTH-SESSION-ID", session.master_session_id}
        ]

    endpoint = "#{@account_payments_endpoint}/#{session.account_id}/chests/orders"

    payload =
      {:form,
       [
         {"master_session_id", session.master_session_id},
         {"chest_id", chest_id},
         {"quantity", quantity},
         {"options", ""}
       ]}

    with {:ok, response} <- APIClient.request(:post, endpoint, additional_headers, payload) do
      Logger.debug("Open chest, resp: #{inspect(response)}")
      :ok
    end
  end
end
