# Trekmap

```
1. Create instance session

curl -H 'Host: nv3-live.startrek.digitgaming.com' \
     -H 'X-Unity-Version: 5.6.4p3' \
     -H 'Accept: */*' \
     -H 'X-PRIME-VERSION: 0.543.8939' \
     -H 'X-Suppress-Codes: 1' \
     -H 'X-PRIME-SYNC: 0' \
     -H 'X-Api-Key: FCX2QsbxHjSP52B' \
     -H 'Accept-Language: ru' \
     -H 'X-TRANSACTION-ID: 9475de9e-d613-49f0-b95d-930f86f185d7' \
     -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' \
     --data "account_id=e4a655634c674cc9aff1b6b7c6c0521a&" \
     'https://nv3-live.startrek.digitgaming.com/accounts/v1/sessions/99a6e9d4fb9e4a899123b62e3989473c/instances'

{"code":200,"instance_session_id":"09b90775ccb8fb4f5ba388ff5f6decbc","account_id":"e4a655634c674cc9aff1b6b7c6c0521a","version":"1.18.9","http_code":201}%

2. Check if instance session is active

curl -H 'Host: nv3-live.startrek.digitgaming.com' \
     -H 'X-Unity-Version: 5.6.4p3' \
     -H 'Accept: */*' \
     -H 'X-PRIME-VERSION: 0.543.8939' \
     -H 'X-Suppress-Codes: 1' \
     -H 'X-PRIME-SYNC: 0' \
     -H 'If-None-Match: W/"7930296748d7850761feef425343610705c93bbe"' \
     -H 'X-Api-Key: FCX2QsbxHjSP52B' \
     -H 'Accept-Language: ru' \
     -H 'X-TRANSACTION-ID: b7d0b307-ac22-48e0-8611-67d62c043d70' \
     -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' \
     --data "" \
     'https://nv3-live.startrek.digitgaming.com/accounts/v1/sessions/1c18e9f3d771496e83c1dd79a4222f67/instances/45fa0b9b38d9f42d8657e841d647b418'

3. List nodes in system

curl -H 'Host: live-193-web.startrek.digitgaming.com' \
     -H 'X-Unity-Version: 5.6.4p3' \
     -H 'Accept: application/x-protobuf' \
     -H 'X-PRIME-VERSION: 0.543.8939' \
     -H 'X-PRIME-SYNC: 0' \
     -H 'Accept-Language: ru' \
     -H 'Content-Type: application/x-protobuf' \
     -H 'X-TRANSACTION-ID: a5dd88cc-d89d-4600-9e2b-03b1bee835df' \
     -H 'X-AUTH-SESSION-ID: 7c2785882b53ffa9a80251c32c99e61b' \
     -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' \
     --data-binary '{"system_id":81673}' \
     'https://live-193-web.startrek.digitgaming.com/game_world/system/dynamic_nodes'

https://gist.github.com/AndrewDryga/aca5c373c7b5d13a2d2bea5aadcd1835

3. Scan users in system

curl -H 'Host: live-193-web.startrek.digitgaming.com' \
      -H 'X-Unity-Version: 5.6.4p3' \
      -H 'Accept: application/x-protobuf' \
      -H 'X-PRIME-VERSION: 0.543.8939' \
      -H 'X-PRIME-SYNC: 0' \
      -H 'Accept-Language: ru' \
      -H 'Content-Type: application/x-protobuf' \
      -H 'X-TRANSACTION-ID: df8bdf79-3b88-42ac-b8f6-ed573c3378d2' \
      -H 'X-AUTH-SESSION-ID: a15fc4082cfd6681fb68a6417f26f8a4' \
      -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' --data-binary '{"target_ids":["v1f1da0c7767401b8f3f4faeb51eae1d","bdb97ae9b9dc40fc89a0b3203450082b","v72b718b166f4a929d8996c8d8877262","b86848d887f64220baa65c582490cc0f","i49934aad0ec405aa9ad2320ed094fe8","u9092014aa1b44b4b74244bfb2065164","uc2191732a584a82a773ca664332949c","q34c0bf1d14444e69741bf6ac43c8885","f59396675aa541c9976226a3d2288fd1","t555540e3ebb42bbb2201c3355f0063b","if6b3f9ff3bb40d6817780392b61afd8","l29f0156aca84b4b93bbfb036e8cb82a","caa0837d319e4a02a1b7394c1698813d","tf0533f56bc4479698ef89d83ef36e78","j46775a5d0834765b229cf4894190012","gb7ecf00bcea4f93a5d16a5dfc2363fa","bf2fa80673ad47d38c4181535ad83da0","u3834ef4307f444894875006974bd74a","zb7d98cd33184fac9148608ee6663e77","c5cce32dff45495599ab8198df9982b5","rcbd10e55cd145d7bfd31c8c3dea2e7a","n6e3b895a0d64f7996c1d1cab08f5ba7","d82918ea56b74261bf2db9184bea661f","a90b66f593fe463ea72fa9679e132ac8","o29a9d9c75e24d85b51a948f96096f35","k756e179fb53485e8b064090a1f8164e","s99334a7d4d043f1a58e2cc12ccc3a20","nac34aa6c5034e6ea1f646166c99c44a","adff4e76fac4492da8cc3fee91f0535d","x873d2e2c4654c208b31e1013ee02fb9","r6f4f671f0784d419ea3dcfce2864b7a","p08bb44cb214407e91f605ba7bad1e4f","j8fff32cff49410f941cfcb99f15b404","ifc06964ec0845309447dce08897ba49","bc9a0967fb454e469af5137696a676d1","we7320f140874904b3570d077cb73429","m1f04bd56bf142dd8ad455cd43fcb1d2","k92fa6e0877e4c7aa08dc3134596c534","uf6a7b30338a467b980d83ca9df2d148","m9a9f046144747e8876e382f6fa40199","c99ea1626c264a31b699970199922725","y5d4cf7996114f90b188c5e855e09b40","n7f1aaa37a984bdab7d0d26eb43944dc","u84d1cb76504434487afc68c3dffecf0","e061f3e2939f4392bff72fbe9927d67f","q45bd8b238504adf9ccdd32100d2b6d9","fe35edf49bae4bff854cba0df73b587d","o8efa8bda891400eaa030d4d2c7af1f0","ba03a97428ef4439858341b8e1d7d766","b95b188ba58849819bdbfe9de7f13cab","od750f86d36949c1ac713789dabf5aa1","k6ba7bfb0ea346bba1be5c96c625703e","m1d24d1735c542e3bd5dd447128567b1","jb46b065f1444be2bcfd7dab528e0af2","daf766e6dba0481da161109db70d4153","n014b263c511400eb279039272f58631","l6d6e86de29e4f8d9310a6f65d2eac5a","tc5494aad8824e30af3b000304c4c26a","s3dcc434477748ce8cd6a266dcb22f98","e115b60adbaa4086888eb1303e95d8b6","k13b4cef47204e338d7ac06e642ea278","b263ec770a88416b8118af206639c161","q0640fbb9abb4e72bd3acac85978639a","q3ed2447823a4c8693ebaed4b1562495","e4b73e26583f4377a788162fc28e020f","e4a655634c674cc9aff1b6b7c6c0521a","ade3e0d53bda45799d1d14912be4f2b1"],"fleet_id":-1,"user_id":"e4a655634c674cc9aff1b6b7c6c0521a","target_type":1}' --compressed 'https://live-193-web.startrek.digitgaming.com/scanning/quick_multi_scan'

4. Scan starbase (fleet id is my ship ID)

curl -H 'Host: live-193-web.startrek.digitgaming.com' \
     -H 'X-Unity-Version: 5.6.4p3' \
     -H 'Accept: application/x-protobuf' \
     -H 'X-PRIME-VERSION: 0.543.8939' \
     -H 'X-PRIME-SYNC: 0' \
     -H 'Accept-Language: ru' \
     -H 'Content-Type: application/x-protobuf' \
     -H 'X-TRANSACTION-ID: 5494c7e7-940d-4ce3-96bc-29d0152adea4' \
     -H 'X-AUTH-SESSION-ID: 6cd99890c4ee7c6f9619b510e0e234e2' \
     -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' \
     --data-binary '{"fleet_id":771246931724024704,"target_user_id":"lb59dde4b6de4e01aa152bd0f52621da"}' \
     'https://live-193-web.startrek.digitgaming.com/scanning/scan_starbase_detailed'

5. Resolve names

https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime?language=en&entity=81673

6. Resolve alliance names

curl -H 'Host: live-193-web.startrek.digitgaming.com' -H 'X-Unity-Version: 5.6.4p3' -H 'Accept: application/x-protobuf' -H 'X-PRIME-VERSION: 0.543.8939' -H 'X-PRIME-SYNC: 0' -H 'Accept-Language: ru' -H 'Content-Type: application/x-protobuf' -H 'X-TRANSACTION-ID: 0e0550e0-c144-4024-8a3f-2ae43b91b0e5' -H 'X-AUTH-SESSION-ID: a15fc4082cfd6681fb68a6417f26f8a4' -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' --data-binary '{"alliance_id":0,"alliance_ids":[748902698409419447,747862113942659589,784471059910255248,759832526260167180,768853838701945454,781568327394157496,765856987186881025,793139308868821601,746856297814975028,770437650363868042,781034855663559501,790778626886230690,773148192421602124,790396395030209501,749475300907573871,756822868821959483,791272419368526810,748893189989360292,784551945250955976,764370635312227050,788774703694504819,763834226335703555,773557585323647961,772215966280344405,788138003532243561,792552961619682251,769890888268014217,748685498742367061,778281493738185690,780171635570664445,794222677383865332,788720708699448152,774898162787050476,759564730234200935,795582556489015951,752582540891939579,793134327470121562,775118042001990239,754873457824916265,792744424559239695,748068513083974203,748649723233461046,747487578970022586,776623875756024559,762018150937420407,760608431446319639,789804513975755506,754436936072323958,772416391071818723,794994397527040717,765746054447915976,774360248458044162,787345254650372946]}' --compressed 'https://live-193-web.startrek.digitgaming.com/alliance/get_alliances_public_info'


curl -H 'Host: live-193-web.startrek.digitgaming.com' -H 'X-Unity-Version: 5.6.4p3' -H 'Accept: application/x-protobuf' -H 'X-PRIME-VERSION: 0.543.8939' -H 'X-PRIME-SYNC: 0' -H 'If-None-Match: W/"4c0b3d6c6ae3e8c21c328146aa9f09783627724b"' -H 'Accept-Language: ru' -H 'Content-Type: application/x-protobuf' -H 'X-TRANSACTION-ID: d71ba29c-09e8-4886-85f9-f9b5cd7f9b8d' -H 'X-AUTH-SESSION-ID: 977df6e08805e45f202cd3720aa7c20f' -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' --compressed 'https://live-193-web.startrek.digitgaming.com/game_world/galaxy_nodes_optimised'

curl -H 'Host: live-193-web.startrek.digitgaming.com' -H 'X-Unity-Version: 5.6.4p3' -H 'Accept: application/x-protobuf' -H 'X-PRIME-VERSION: 0.543.8939' -H 'X-PRIME-SYNC: 2' -H 'Accept-Language: ru' -H 'Content-Type: application/x-protobuf' -H 'X-TRANSACTION-ID: 64d169d1-cb67-4297-8c93-8d37d8a4f5e8' -H 'X-AUTH-SESSION-ID: 977df6e08805e45f202cd3720aa7c20f' -H 'User-Agent: startrek/0.543.8939 CFNetwork/976 Darwin/18.2.0' --data-binary "" --compressed 'https://live-193-web.startrek.digitgaming.com/sync'
```

Planet coords:
```
([
  ["Tuoue", 0, "LordIronman", {327, -356}, {370, -391}],
  ["Tuoue", 1, "AuroraNavis", {327, -356}, {382, -361}],
  ["Tuoue", 2, "Pippy", {327, -356}, {284, -321}],
  ["Tuoue", 3, "dcamel", {327, -356}, {272, -351}],
  ["Tuoue", 4, "d3athLorD3", {327, -356}, {362, -313}],
  ["Tuoue", 5, "SalmonSensay", {327, -356}, {332, -301}],
  ["Tuoue", 6, "CapinNeemo", {327, -356}, {292, -399}],
  ["Tuoue", 7, "WhiteGhost", {327, -356}, {322, -411}],
  ["Tuoue", 8, "zzzed36", {327, -356}, {397, -413}],
  ["Tuoue", 9, "Fr3ak", {327, -356}, {417, -364}],
  ["Tuoue", 10, "SweatyYetiNZ", {327, -356}, {257, -299}],
  ["Tuoue", 11, "Matt1983", {327, -356}, {237, -348}],
  ["Tuoue", 12, "Gargantuan", {327, -356}, {384, -286}],
  ["Tuoue", 13, "YelilWerdna", {327, -356}, {335, -266}],
  ["Tuoue", 14, "CapitanBigdeckNZ", {327, -356}, {270, -426}],
  ["Tuoue", 15, "Shilo", {327, -356}, {319, -446}]
]
|> Enum.map(fn l ->
  [{x1, y1} = station_coords, {x2, y2} = planet_coords, _name, index, _] = Enum.reverse(l)
  [index, station_coords, planet_coords, {x1 - x2, y1 - y2}]
end))

([
  ["Witafan", 0, "Kpbek", {-489, 177}, {-446, 142}],
  ["Witafan", 1, "Sundog", {-489, 177}, {-434, 172}],
  ["Witafan", 2, "AngryKnight", {-489, 177}, {-532, 212}],
  ["Witafan", 3, "Runefaust", {-489, 177}, {-544, 182}],
  ["Witafan", 4, "Pash931", {-489, 177}, {-454, 220}],
  ["Witafan", 5, "Mallytime", {-489, 177}, {-484, 232}],
  ["Witafan", 6, "Aseop64", {-489, 177}, {-524, 134}],
  ["Witafan", 7, "Grondok", {-489, 177}, {-494, 122}],
  ["Witafan", 8, "strawberrye1", {-489, 177}, {-419, 120}],
  ["Witafan", 9, "JDBuzzman", {-489, 177}, {-399, 169}],
  ["Witafan", 10, "MadScavenger", {-489, 177}, {-559, 234}],
  ["Witafan", 11, "Hossen27", {-489, 177}, {-579, 185}],
  ["Witafan", 12, "EggWaffle", {-489, 177}, {-432, 247}],
  ["Witafan", 13, "HansHammersmith", {-489, 177}, {-481, 267}],
  ["Witafan", 14, "GalacticDrift", {-489, 177}, {-546, 107}],
  ["Witafan", 15, "ozscience", {-489, 177}, {-497, 87}]
]
|> Enum.map(fn l ->
  [{x1, y1} = station_coords, {x2, y2} = planet_coords, _name, index, _] = Enum.reverse(l)
  [index, station_coords, planet_coords, {x1 - x2, y1 - y2}]
end))
```
