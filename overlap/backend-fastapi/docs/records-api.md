# Records and personalized feed

Authenticated endpoints:
- `POST /records`: multipart `data` JSON plus 1–5 `photos` files (JPEG/PNG/WebP, each up to 10MB).
- `GET /records/groups`: actual memberships from `memory_groups` and `group_members`.
- `GET /feed`: own records and non-private records shared to joined groups. Optional `mine=true`, `group_id`, `offset`, `limit`.
- `GET /records/{id}/photos/{photo_id}`: authorized photo stream through FastAPI; private Object Storage objects are not made public.

`data` includes `place` (`kakao_place_id`, `name`, `address`, `latitude`, `longitude`), `emotion` (`excellent`, `good`, `okay`, `neutral`, `disappointed`, `poor`), optional `content` (maximum 300 characters), `is_private`, and `group_ids`. Photos, emotion and place are required. Private records cannot include groups; shared records require actual membership in every chosen group.

Run `python scripts/add_record_photo_url.py` once before using these endpoints. This idempotent migration adds nullable `record_photos.photo_url VARCHAR(500)` and preserves `object_key` and all existing rows/tables. New uploads store both object keys and canonical URLs; no image bytes go into MySQL. Response photo URLs are protected FastAPI routes.

Set `NCP_ACCESS_KEY`, `NCP_SECRET_KEY`, `NCP_BUCKET_NAME`, and `NCP_ENDPOINT` in backend `.env` only. The endpoint must be HTTPS (the Object Storage endpoint for the bucket region). Use credentials permitted to upload/read/delete objects in that bucket. No placeholder credentials or automatic bucket creation are provided. Missing configuration returns 503. `.env` is excluded by the existing `.gitignore`.

Storage tests use an injected fake storage client and isolated SQLite databases; they do not upload to NCP or write to production MySQL. Live upload verification requires the four environment settings.
