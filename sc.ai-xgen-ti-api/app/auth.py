import os, hmac
from typing import Optional, List
from fastapi import Header, HTTPException, status

def _load_keys() -> List[str]:
    raw = os.getenv("API_KEYS", "")
    return [k.strip() for k in raw.split(",") if k.strip()]

API_KEYS = _load_keys()

def _valid(provided: str) -> bool:
    for k in API_KEYS:
        if hmac.compare_digest(provided, k):
            return True
    return False

async def require_api_key(authorization: Optional[str] = Header(None), x_api_key: Optional[str] = Header(None)):
    if not API_KEYS:
        return
    token = None
    if x_api_key:
        token = x_api_key
    elif authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    if token and _valid(token):
        return
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
