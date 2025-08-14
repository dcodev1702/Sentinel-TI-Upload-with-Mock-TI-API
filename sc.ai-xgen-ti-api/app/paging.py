import base64, json
from typing import Optional

def encode_token(offset: int) -> str:
    payload = {"o": int(offset)}
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")

def decode_token(token: Optional[str]) -> int:
    if not token:
        return 0
    try:
        pad = "=" * (-len(token) % 4)
        data = base64.urlsafe_b64decode(token + pad)
        payload = json.loads(data.decode("utf-8"))
        return int(payload.get("o", 0))
    except Exception:
        return 0
