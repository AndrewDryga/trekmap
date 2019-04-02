defmodule Trekmap.Me.Name do
  alias Trekmap.{APIClient, Session}

  @accounts_endpoint "https://nv3-live.startrek.digitgaming.com/accounts/v1/accounts"

  @prefix [
    "Bloodthirsty",
    "Sneaky",
    "Epic",
    "Legendary",
    "Allmighty",
    "Godlike",
    "Harmless",
    "Aggressive",
    "Happy",
    "Angry",
    "Excited",
    "Curious",
    "Commander",
    "General",
    "Babies",
    "Saint",
    "Immortal",
    "Fatal"
  ]

  @name [
    "Unicorn",
    "Priest",
    "Kitty",
    "Panda",
    "Lemoore",
    "Owl",
    "Baby",
    "SoulReaper"
  ]

  @suffix [
    "Seeker",
    "Exorcist",
    "Punisher",
    "Puncher",
    "Predator",
    "Rapist",
    "Slacker",
    "Killer",
    "Hunter",
    "Lover"
  ]

  def generate_name do
    words = Enum.random([2, 3])

    case words do
      1 -> Enum.random(@name)
      2 -> Enum.random(@prefix) <> Enum.random(@name)
      3 -> Enum.random(@prefix) <> Enum.random(@name) <> Enum.random(@suffix)
    end
  end

  def change_name(name, %Session{} = session) do
    additional_headers = Session.additional_headers()

    endpoint =
      "#{@accounts_endpoint}/#{session.master_account_id}/instance_accounts/#{session.account_id}"

    payload =
      {:form,
       [
         {"session_id", session.master_session_id},
         {"language", "EN"},
         {"name", name}
       ]}

    with {:ok, _response} <- APIClient.json_request(:post, endpoint, additional_headers, payload) do
      :ok
    end
  end
end
