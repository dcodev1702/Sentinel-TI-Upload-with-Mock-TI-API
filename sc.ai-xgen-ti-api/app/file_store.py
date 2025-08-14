import json, os
from datetime import datetime
from typing import List, Dict, Any, Optional, Iterable

def _parse_dt(s: str) -> datetime:
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return datetime(1970,1,1)

def _key(o: Dict[str, Any]):
    ts = o.get("valid_from") or o.get("created") or "1970-01-01T00:00:00Z"
    return _parse_dt(ts)

def load_objects(data_dir: str, since: Optional[str] = None, limit: Optional[int] = None, types: Optional[Iterable[str]] = None) -> Dict[str, Any]:
    objects: Dict[str, Dict[str, Any]] = {}
    since_dt: Optional[datetime] = None
    if since:
        since_dt = _parse_dt(since)

    for root, _, files in os.walk(data_dir):
        for name in sorted(files):
            if not name.lower().endswith(".json"):
                continue
            full = os.path.join(root, name)
            try:
                with open(full, "r", encoding="utf-8") as fh:
                    payload = json.load(fh)
            except Exception:
                continue

            objs = payload.get("stixobjects", [])
            for obj in objs:
                if not isinstance(obj, dict):
                    continue
                if obj.get("spec_version") != "2.1":
                    continue
                if types and obj.get("type") not in types:
                    continue
                ts = obj.get("valid_from") or obj.get("created")
                if since_dt and ts:
                    try:
                        obj_dt = _parse_dt(ts)
                        if obj_dt < since_dt:
                            continue
                    except Exception:
                        pass
                oid = obj.get("id")
                if oid and oid not in objects:
                    objects[oid] = obj

    merged = sorted(objects.values(), key=_key, reverse=True)
    if isinstance(limit, int) and limit > 0:
        merged = merged[:limit]
    return {"count": len(merged), "stixobjects": merged}

def load_indicators(data_dir: str, since: Optional[str] = None, limit: Optional[int] = None) -> Dict[str, Any]:
    return load_objects(data_dir, since=since, limit=limit, types=["indicator"])
