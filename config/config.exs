use Mix.Config

config :trekmap, Trekmap.Session,
  api_key: "FCX2QsbxHjSP52B",
  account_id: "e4a655634c674cc9aff1b6b7c6c0521a",
  username: "dgt1g148301fcf1a46188c38c26dfc48f9dc",
  password: "dgt1e8d857a5e1cb4cc6a72b3ec0cd8da9d9"

config :trekmap, Trekmap.AirDB,
  api_key: "keypqweij1k3jaI0m",
  endpoint: "https://api.airtable.com/v0",
  base_id: "appoB3R8Hs39k5GHd"

config :trekmap,
  auth: [
    username: "andrew",
    password: "iscool",
    realm: "Admin Area"
  ]
