import json
from urllib.request import urlopen

url = "http://localhost:18080/realms/shinyoauthdb/protocol/openid-connect/certs"
with urlopen(url, timeout=30) as response:
    keys = json.load(response)
with open("/jwks/keys.json", "w", encoding="utf-8") as output:
    json.dump(keys, output)
