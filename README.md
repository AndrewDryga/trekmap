# Trekmap

This is an example how a bot for Star Trek Fleet Command (a game for iOS and Android) can look like. It's provided only for EDUCATIONAL purposes DO NOT USE IT WITH REAL GAME or your account would be banned.

It was tested 2 years ago when with some investment (refunded later rebating in-app purchase via Apple because game is buggy) allowed to dominate over entire server.

The code is not clean, it's built pretty ad-hoc to in-game situation.

## How to make it run?

1. Example includes inactive account and server data for one of STFC servers in Asia, they need to be replaced. [Authentication requests with your tokens can be recorded with Charles proxy](https://www.raywenderlich.com/1827524-charles-proxy-tutorial-for-ios). 

2. It uses Airtable as persistent storage, you would need to connect an Airtable database [like this one](https://airtable.com/shrV9XgJ4w7nJQUnv).

3. There is plenty of strategies for a bot, they are configured just as an example. You should replace values that fit best for your use case.

4. Ships and ship IDs are also hardcoded because this is an example and I'm lazy to generalize everything :).

5. You can use Gigalixir to deploy it so that it runs 24/7. Keep in mind that it's not possible to log in from two devices so you would need to pause bot every time you want to log in.

Have fun.
