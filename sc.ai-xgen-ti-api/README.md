# Mock STIX/TAXII 2.1 TI API (Indicators + Mixed Types)

- FastAPI app with in-container generator (every 3 hours by default).
- Auth via `API_KEYS` (X-API-Key or Bearer).
- Flat, collection, and TAXII endpoints.
- Cursor paging (`next`), `types=` filters, and TAXII `ETag`/`Last-Modified`.
- **Top-level `sourcesystem` field** included in list responses.

## Build & Run
```bash
docker build -t mock-sc-xgen-ti-api-alpine .
mkdir -p ./data
docker run -d --name mock-sc-xgen-ti-api -p 80:8080 -v $PWD/data:/app/data --env-file .\.env  mock-sc-xgen-ti-api-alpine:latest
```

## API Endpoint Tree Structure

```
/
├── healthz                                    [GET]    # Health check (no auth)
|__ routes                                     [GET]    # Displays API endpoints (no auth)
│
├── api/
│   └── v1/
│       ├── ti-generator                      [POST]   # Generate new TI indicators
|       ├── ctf-cookiez                       [GET]    # Get CTF Flag
│       ├── ti-delete                         [DELETE] # Delete old indicator files
│       ├── indicators                        [GET]    # Get indicators with paging
│       └── collections/                      
│           ├── (root)                        [GET]    # List collections
│           └── {id}/
│               └── objects                   [GET]    # Get collection objects
│
└── taxii2/
    ├── (root)                                [GET]    # TAXII Discovery
    └── root/
        └── collections/
            ├── (root)                        [GET]    # List TAXII collections
            └── {id}/
                └── objects                   [GET]    # Get TAXII objects
```

## Endpoint Details

### Health & Status
- `GET /healthz` - Health check endpoint  (no auth required)
- `GET /routes`  - Displays API Endpoints (no auth required)

### TI Management
- `POST /api/v1/ti-generator` - Generate new pseudo-random TI indicators
  - Creates synthetic STIX indicators and stores them in the data directory
  - Response: `{ status, message, filename, indicators_count, timestamp }`
  
- `DELETE /api/v1/ti-delete?h=9` - Delete old TI indicator files
  - Deletes JSON files older than specified hours (default 9)
  - Query param: `h` - hours threshold for deletion
  - Response: `{ status, deleted_files, total_deleted, threshold_hours, timestamp }`

### Data Retrieval
- `GET /api/v1/indicators?since=...&page_size=...&next=...`
  - Response: `{ count, total, more, next, sourcesystem, stixobjects }`
  
- `GET /api/v1/ctf-cookiez`
  - Response: `{msg, flag}`
  
- `GET /api/v1/collections`
  - Lists available collections
  
- `GET /api/v1/collections/{id}/objects?since=...&types=indicator,attack-pattern&page_size=...&next=...`
  - Response: `{ objects, sourcesystem, total, more, next }`

### TAXII 2.1 Endpoints
- `GET /taxii2/` - TAXII Discovery
- `GET /taxii2/root/collections` - List TAXII collections
- `GET /taxii2/root/collections/{id}/objects?limit=...&added_after=...&types=...&next=...`
  - Response (`application/taxii+json`): `{ objects, sourcesystem, more, next }` with `ETag`, `Last-Modified`

## Authentication
All endpoints except `/healthz` require authentication via API keys when `API_KEYS` is configured:
- Header: `X-API-Key: your-key`
- Or Bearer token: `Authorization: Bearer your-key`

## Automatic Generation
The API automatically generates new TI indicators every 3 hours (configurable via `GENERATE_EVERY_SECONDS`). This happens in the background using the internal generator.

## Environment Variables
See `.env.example`. Notable:
- `API_KEYS` — comma-separated keys (enables auth when set)
- `GENERATE_EVERY_SECONDS` — default 10800 (3h)
- `GENERATE_ON_START` — generate indicators on startup (default true)
- `MIN_COUNT` / `MAX_COUNT` — min/max indicators per generation (default 10-25)
- `TAXII_INDICATORS_ONLY` — force TAXII to indicators only
- `SOURCE_SYSTEM` — defaults to `STEELCAGE.AI X-GEN TI PLATFORM`
- `DATA_DIR` — directory for storing indicator JSON files (default `/app/data`)

## Data Storage
- Indicators are stored as JSON files in the `DATA_DIR` directory
- Files are named with timestamp: `indicators_YYYYMMDDTHHMMSS.SSSSSSZ.json`
- Multiple files can exist; the API aggregates all files when serving requests
- Use the `/api/v1/ti-delete` endpoint to clean up old files

## API Usage Examples

### 1. Get List of All Indicators

```bash
# Using curl with X-API-Key header
curl -X GET "http://localhost:8080/api/v1/indicators" \
  -H "X-API-Key: your-api-key-here"

# Using curl with Bearer token
curl -X GET "http://localhost:8080/api/v1/indicators" \
  -H "Authorization: Bearer your-api-key-here"

# With pagination (page_size and next token)
curl -X GET "http://localhost:8080/api/v1/indicators?page_size=50" \
  -H "X-API-Key: your-api-key-here"

# Filter indicators created after specific date
curl -X GET "http://localhost:8080/api/v1/indicators?since=2025-08-10T00:00:00Z" \
  -H "X-API-Key: your-api-key-here"
```

**Example Response:**
```json
{
  "count": 25,
  "total": 25,
  "more": false,
  "next": null,
  "sourcesystem": "STEELCAGE.AI X-GEN TI PLATFORM",
  "stixobjects": [
    {
      "type": "indicator",
      "id": "indicator--b8fb1719-e30c-4545-a1e9-9ec8e540d182",
      "pattern": "[file:hashes.MD5 = 'b13f5051dca94fdb95169b7351d35df9']",
      ...
    }
  ]
}
```

### 2. Delete TI Indicators Older Than 6 Hours

```bash
# Delete files older than 6 hours (override default 9 hours)
curl -X DELETE "http://localhost:8080/api/v1/ti-delete?h=6" \
  -H "X-API-Key: your-api-key-here"

# Delete using default 9 hours threshold
curl -X DELETE "http://localhost:8080/api/v1/ti-delete" \
  -H "X-API-Key: your-api-key-here"

# Delete files older than 24 hours
curl -X DELETE "http://localhost:8080/api/v1/ti-delete?h=24" \
  -H "X-API-Key: your-api-key-here"
```

**Example Response:**
```json
{
  "status": "successful",
  "deleted_files": [
    "indicators_20250812T023816.114378Z.json",
    "indicators_20250812T053816.223445Z.json"
  ],
  "total_deleted": 2,
  "threshold_hours": 6,
  "timestamp": "2025-08-12T15:30:00.123456Z"
}
```

### 3. Generate New TI Indicators

```bash
# Generate new TI indicators
curl -X POST "http://localhost:8080/api/v1/ti-generator" \
  -H "X-API-Key: your-api-key-here"

# Using Bearer token
curl -X POST "http://localhost:8080/api/v1/ti-generator" \
  -H "Authorization: Bearer your-api-key-here"
```

**Example Response:**
```json
{
  "status": "successful",
  "message": "TI indicators generated successfully",
  "filename": "indicators_20250812T153000.456789Z.json",
  "indicators_count": 18,
  "timestamp": "2025-08-12T15:30:00.456789Z"
}
```

### Python Examples

```python
import requests

# Configuration
BASE_URL = "http://localhost:8080"
API_KEY = "your-api-key-here"
headers = {"X-API-Key": API_KEY}

# 1. Get all indicators
response = requests.get(f"{BASE_URL}/api/v1/indicators", headers=headers)
indicators = response.json()
print(f"Total indicators: {indicators['total']}")

# 2. Delete TI older than 6 hours
response = requests.delete(f"{BASE_URL}/api/v1/ti-delete?h=6", headers=headers)
result = response.json()
print(f"Deleted {result['total_deleted']} files")

# 3. Generate new TI indicators
response = requests.post(f"{BASE_URL}/api/v1/ti-generator", headers=headers)
result = response.json()
print(f"Generated {result['indicators_count']} indicators in {result['filename']}")
```

### Testing Without Authentication
If `API_KEYS` environment variable is not set or empty, you can call the endpoints without authentication:

```bash
# No auth header needed when API_KEYS is not configured
curl -X GET "http://localhost:8080/api/v1/indicators"
curl -X POST "http://localhost:8080/api/v1/ti-generator"
curl -X DELETE "http://localhost:8080/api/v1/ti-delete?h=6"
```
