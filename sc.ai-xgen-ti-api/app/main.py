import os, asyncio, hashlib
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, Query, Request, HTTPException, Depends, APIRouter
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from .file_store import load_indicators, load_objects
from .generator import generate_payload, write_payload
from .paging import encode_token, decode_token
from .auth import require_api_key

load_dotenv()

# Environment variables
DATA_DIR = os.getenv("DATA_DIR", "/app/data")
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8080"))
KERNEL_VERSION = "Linux slackware-arm64 6.15.3-arm64-slack #1 SMP PREEMPT Thu Aug 14 10:32:45 UTC 2025 aarch64 GNU/Linux"
OS_RELEASE = "Slackware ARM64 Embedded"
ARCH = "aarch64"
API_BUILD_HASH = os.getenv("API_BUILD", "DCODEV1702")
CORS_ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
GENERATE_EVERY_SECONDS = int(os.getenv("GENERATE_EVERY_SECONDS", str(2 * 60 * 60)))
GENERATE_ON_START = os.getenv("GENERATE_ON_START", "true").lower() == "true"
MIN_COUNT = int(os.getenv("MIN_COUNT", "10"))
MAX_COUNT = int(os.getenv("MAX_COUNT", "25"))
TAXII_API_ROOT_PATH = os.getenv("TAXII_API_ROOT_PATH", "/taxii2/root")
COLLECTION_ID = os.getenv("COLLECTION_ID", "indicators")
COLLECTION_TITLE = os.getenv("COLLECTION_TITLE", "SC.AI X-GEN TI Synthetic Indicators (STIX 2.1)")
TAXII_INDICATORS_ONLY = os.getenv("TAXII_INDICATORS_ONLY", "false").lower() == "true"
SOURCE_SYSTEM = os.getenv("SOURCE_SYSTEM", "STEELCAGE.AI X-GEN TI PLATFORM")
API_VERSION = os.getenv("API_VERSION", "1702.93.3082")
API_KEYS = os.getenv("API_KEYS", "").split(",")

# FastAPI app
app = FastAPI(title="Mock X-GEN TI REST API", version=API_VERSION, description="Mock X-GEN STIX/TAXII 2.1 Threat Intelligence REST API")

if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# ----------------- Helpers -----------------
def _mask_sensitive_value(value: str) -> str:
    length = len(value)
    if length <= 8:
        return value
    return f"{value[:4]}{'*' * (length - 8)}{value[-4:]}"

def _parse_types_param(types_param: Optional[str]) -> Optional[List[str]]:
    if not types_param:
        return None
    parts = [t.strip() for t in types_param.split(",") if t.strip()]
    return parts or None

def _collect_items(since: Optional[str], types: Optional[List[str]]) -> List[Dict[str, Any]]:
    merged = load_objects(DATA_DIR, since=since, limit=10_000, types=types)["stixobjects"]
    return merged

def _page(items: List[Dict[str, Any]], offset: int, page_size: int):
    total = len(items)
    start = max(offset, 0)
    end = min(start + page_size, total)
    slice_ = items[start:end]
    more = end < total
    next_token = encode_token(end) if more else None
    return slice_, total, more, next_token

# ----------------- Startup Background Task -----------------
@app.on_event("startup")
async def _start_generator():
    if GENERATE_ON_START:
        payload = generate_payload(min_count=MIN_COUNT, max_count=MAX_COUNT)
        write_payload(DATA_DIR, payload)

    async def _loop():
        while True:
            try:
                await asyncio.sleep(GENERATE_EVERY_SECONDS)
                payload = generate_payload(min_count=MIN_COUNT, max_count=MAX_COUNT)
                write_payload(DATA_DIR, payload)
            except Exception as e:
                print(f"[generator] error: {e}")
                await asyncio.sleep(10)

    asyncio.create_task(_loop())

# ----------------- Root Health Endpoint -----------------
@app.get("/healthz")
def healthz():
    genai_info = [
        {
            "GenAI-Model": "SKYNET.AI",
            "GenAI-Engine": "8.3.90283128853",
            "GenAI-Model-Status": "online",
            "GenAI-Enabled": "true",
            "PowerSource": "Nuclear",
            "Transport": "Quantum"
        }
    ]
    system_info = {
        "kernel_version": KERNEL_VERSION,
        "os_release": OS_RELEASE,
        "architecture": ARCH
    }
    return {
        "status": "ok",
        "host": HOST,
        "port": PORT,
        "mrrobot": "Hello, friend.",
        "api_keys": _mask_sensitive_value(API_KEYS[0]),
        "sourcesystem": SOURCE_SYSTEM,
        "api_version": API_VERSION,
        "api_build_hash": API_BUILD_HASH,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "additional info": "SC.AI X-GEN TI REST API",
        "system_info": system_info,
        "GenAI": genai_info
    }

# ----------------- Routers -----------------
api_router = APIRouter(prefix="/api/v1", tags=["TI API"])
taxii_router = APIRouter(prefix="/taxii2", tags=["TAXII API"])


@app.get("/routes")
def list_routes():
    return [route.path for route in app.routes]


@api_router.get("/ctf-cookiez", dependencies=[Depends(require_api_key)])
def get_ctf_cookiez():
    return JSONResponse(content={
        "msg": "UNLOCKED::MSG Request received",
        "flag": "wh3r3_th3_c00k13z_n_sh1t!?"
    })


# ---- API Router Endpoints ----
@api_router.post("/ti-generator", dependencies=[Depends(require_api_key)])
def generate_ti_indicators():
    payload = generate_payload(min_count=MIN_COUNT, max_count=MAX_COUNT)
    file_path = write_payload(DATA_DIR, payload)
    filename = os.path.basename(file_path)
    return JSONResponse(content={
        "status": "successful",
        "message": "TI indicators generated successfully",
        "filename": filename,
        "indicators_count": len(payload.get("stixobjects", [])),
        "timestamp": datetime.now(timezone.utc).isoformat()
    })

@api_router.delete("/ti-delete", dependencies=[Depends(require_api_key)])
def delete_old_ti_files(h: Optional[int] = Query(6)):
    deleted_files = []
    current_time = datetime.now(timezone.utc)
    threshold = current_time - timedelta(hours=h)
    for root, _, files in os.walk(DATA_DIR):
        for filename in files:
            if filename.lower().endswith('.json') and filename.startswith('indicators_'):
                file_path = os.path.join(root, filename)
                file_mtime = datetime.fromtimestamp(os.path.getmtime(file_path), tz=timezone.utc)
                if file_mtime < threshold:
                    os.remove(file_path)
                    deleted_files.append(filename)
    return JSONResponse(content={
        "status": "successful",
        "deleted_files": deleted_files,
        "total_deleted": len(deleted_files),
        "threshold_hours": h,
        "timestamp": datetime.now(timezone.utc).isoformat()
    })

@api_router.get("/indicators", dependencies=[Depends(require_api_key)])
def get_indicators(since: Optional[str] = None, limit: Optional[int] = None, page_size: Optional[int] = None, next: Optional[str] = None):
    items = load_indicators(DATA_DIR, since=since, limit=10_000)["stixobjects"]
    if page_size is None:
        page_size = limit or len(items)
    offset = decode_token(next)
    page, total, more, next_token = _page(items, offset, page_size)
    return JSONResponse(content={
        "count": len(page),
        "total": total,
        "more": more,
        "next": next_token,
        "sourcesystem": SOURCE_SYSTEM,
        "stixobjects": page
    })

@api_router.get("/collections", dependencies=[Depends(require_api_key)])
def list_collections():
    return {"collections": [{
        "id": COLLECTION_ID,
        "title": COLLECTION_TITLE,
        "type": "mixed",
        "can_read": True,
        "can_write": False
    }]}

@api_router.get("/collections/{collection_id}/objects", dependencies=[Depends(require_api_key)])
def get_collection_objects(collection_id: str, since: Optional[str] = None, types: Optional[str] = None, page_size: int = 100, next: Optional[str] = None):
    if collection_id != COLLECTION_ID:
        raise HTTPException(status_code=404, detail="Collection not found")
    type_list = _parse_types_param(types)
    items = _collect_items(since, types=type_list)
    offset = decode_token(next)
    page, total, more, next_token = _page(items, offset, page_size)
    return {
        "objects": page,
        "sourcesystem": SOURCE_SYSTEM,
        "total": total,
        "more": more,
        "next": next_token
    }

# ---- TAXII Router Endpoints ----
@taxii_router.get("/", summary="TAXII Discovery", dependencies=[Depends(require_api_key)])
def taxii_discovery(request: Request):
    base = str(request.base_url).rstrip("/")
    api_root = f"{base}{TAXII_API_ROOT_PATH}"
    return JSONResponse(content={
        "title": "Mock TAXII Server",
        "description": "Discovery document for the mock TAXII 2.1 API",
        "default": api_root,
        "api_roots": [api_root]
    }, media_type="application/taxii+json")

@taxii_router.get("/root/collections", summary="TAXII Collections", dependencies=[Depends(require_api_key)])
def taxii_collections():
    return JSONResponse(content={
        "collections": [{
            "id": COLLECTION_ID,
            "title": COLLECTION_TITLE,
            "description": "Synthetic STIX 2.1 content generated inside the container.",
            "can_read": True,
            "can_write": False,
            "media_types": ["application/stix+json;version=2.1"]
        }]
    }, media_type="application/taxii+json")

@taxii_router.get("/root/collections/{collection_id}/objects", summary="TAXII Objects", dependencies=[Depends(require_api_key)])
def taxii_objects(request: Request, collection_id: str, added_after: Optional[str] = None, limit: int = 100, next: Optional[str] = None, types: Optional[str] = None):
    if collection_id != COLLECTION_ID:
        raise HTTPException(status_code=404, detail="Collection not found")
    type_list = ["indicator"] if TAXII_INDICATORS_ONLY else _parse_types_param(types)
    items = _collect_items(added_after, types=type_list)
    offset = decode_token(next)
    page, total, more, next_token = _page(items, offset, limit)
    last_modified = datetime.utcnow()
    extras = f"types={','.join(type_list) if type_list else 'all'};total={total}"
    etag = f'W/"{hashlib.sha256((last_modified.isoformat() + "|" + str(len(items)) + "|" + extras).encode()).hexdigest()[:16]}"'
    last_modified_http = last_modified.strftime("%a, %d %b %Y %H:%M:%S GMT")
    return JSONResponse(
        content={"objects": page, "sourcesystem": SOURCE_SYSTEM, "more": more, "next": next_token},
        media_type="application/taxii+json",
        headers={"ETag": etag, "Last-Modified": last_modified_http}
    )

# Include routers
app.include_router(api_router)
app.include_router(taxii_router)
