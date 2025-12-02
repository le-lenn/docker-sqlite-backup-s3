# Docker SQLite to S3

SQLite backup utility which backups your sqlite to S3. All configurable via environment variables.


## Usage

## Environment Variables

| Variable        | Description      | Example Usage  | Default   | Required |
| --------------- |:---------------:| -----:| -----:| --------:|
| `S3_BUCKET`               | Name of bucket | `mybucketname` | None | Yes |
| `S3_KEY_PREFIX` | S3 directory to place files in | `backups` or `backups/sqlite` | None | No |
| `AWS_ACCESS_KEY_ID`       | AWS Access key | `AKIAIO...` | None      | Yes (unless using instance role) |
| `AWS_SECRET_ACCESS_KEY`   |  AWS Secret Key |  `wJalrXUtnFE...` | None   | Yes (unless using instance role) |
| `AWS_DEFAULT_REGION`   | AWS Default Region | `us-west-2`    | `us-west-1`   | No |
| `DATABASE_PATH` | Path of database to be backed up (within the container)   | `/myvolume/mydb.db` | None   | Yes |
| `BACKUP_PATH` | Path to write the backup (within the container)  | `/myvolume/mybackup.db` | `${DATABASE_PATH}.bak`   | No |
| `ENDPOINT_URL` | URL to S3-compatible endpoint (MinIO, Cloudflare R2, Wasabi) | `https://play.minio.com:9000` | None | No |
| `SQLITE_TIMEOUT_MS` | Busy timeout used by SQLite `.backup`/`.restore` (milliseconds) | `10000` | `10000` | No |
| `CRON_SCHEDULE` | Cron expression for scheduled backups (cron mode only) | `0 1 * * *` | None | Yes (cron mode only) |
| `POST_WEBHOOK_URL` | URL to call with a POST after successful backup | `https://example.com/hook` | None | No |
| `ENCRYPTION_KEY` | If set, encrypt backups before upload. Required to restore encrypted backups. | `your-strong-passphrase` | None | No (required to restore encrypted backups) |


## Docker Compose

You can run this container as a sidecar alongside your application and have it back up the SQLite database on a schedule, and trigger restores when needed.

### Backup sidecar (scheduled cron)

```yaml

volumes:
  app-data:

services:
  app:
    image: your-app-image:latest
    # Ensure your app writes its SQLite DB to /data/sqlite3.db
    volumes:
      - app-data:/data

  sqlite-backup:
    image: ghcr.io/le-lenn/docker-sqlite-to-s3:latest
    # Mount the same volume as the app, read-only is sufficient for backup
    volumes:
      - app-data:/data:ro
    environment:
      DATABASE_PATH: /data/sqlite3.db
      CRON_SCHEDULE: "0 1 * * *"
      S3_BUCKET: your-bucket
      S3_KEY_PREFIX: backups/sqlite/
      AWS_ACCESS_KEY_ID: your-access-key
      AWS_SECRET_ACCESS_KEY: your-secret-key
      AWS_DEFAULT_REGION: us-west-2
      # Optional: if using an S3-compatible provider (MinIO, Cloudflare R2, Wasabi)
      # ENDPOINT_URL: https://your-provider-endpoint
      # Optional: tune backup/restore busy timeout (ms), default 10000
      # SQLITE_TIMEOUT_MS: 10000
      # Optional: notify another service when a backup completes
      # POST_WEBHOOK_URL: https://example.com/myhook
      # Optional: set if your DB is not at the default path
      # DATABASE_PATH: /data/yourdb.sqlite
      # Optional: encrypt backups before upload
      # ENCRYPTION_KEY: your-strong-passphrase
    # Run on a daily schedule at 1am (controlled via CRON_SCHEDULE)
    command: ["cron"]
    restart: unless-stopped
    depends_on:
      - app
```

### Restore (one-off)

Ensure your application is not started while restoring (either stop it or only start selected services), then run a one-off restore using Compose:

```yaml
volumes:
  app-data:

services:
  # ... your app and sqlite-backup services from above, but commented out ro not selected ...

  sqlite-restore:
    image: ghcr.io/le-lenn/docker-sqlite-to-s3:latest
    volumes:
      - app-data:/data
    environment:
      DATABASE_PATH: /data/sqlite3.db
      S3_BUCKET: your-bucket
      S3_KEY_PREFIX: backups/sqlite/
      AWS_ACCESS_KEY_ID: your-access-key
      AWS_SECRET_ACCESS_KEY: your-secret-key
      AWS_DEFAULT_REGION: us-west-2
      # ENDPOINT_URL: https://your-provider-endpoint
      # DATABASE_PATH: /data/yourdb.sqlite
      # SQLITE_TIMEOUT_MS: 10000
      # If backups are encrypted, you must set the same key here
      # ENCRYPTION_KEY: your-strong-passphrase
    # Use a timestamp argument (YYYYMMDDHHMMSS)
    command: ["restore", "20240131120000"]
    restart: "no"
    profiles: ["restore"]
```

## Gotchas

- Read-only volume during restore: For restores you must mount the shared volume read-write. Example difference: backup sidecar can use `:ro`, restore service must not.
- App running during restore: If the app is up it may keep SQLite files open and block `.restore`. Do not start the app when restoring.
- Encrypted backups: When `ENCRYPTION_KEY` is set, backups are encrypted before upload. To restore an encrypted backup you must provide the same `ENCRYPTION_KEY`; otherwise restore fails with an explanatory error.
- Ensure the database file path inside the containers matches `DATABASE_PATH`
