# Docker SQLite to S3

SQLite backup utility which backups your sqlite to S3. All configurable via environment variables.


## Usage

## Environment Variables

| Variable        | Description      | Example Usage  | Default   | Required |
| --------------- |:---------------:| -----:| -----:| --------:|
| `S3_BUCKET`               | Name of bucket | `mybucketname` | None | Yes |
| `S3_PREFIX` | S3 directory to place files in | `backups` or `backups/sqlite` | None | No |
| `AWS_ACCESS_KEY_ID`       | AWS Access key | `AKIAIO...` | None      | Yes (unless using instance role) |
| `AWS_SECRET_ACCESS_KEY`   |  AWS Secret Key |  `wJalrXUtnFE...` | None   | Yes (unless using instance role) |
| `AWS_DEFAULT_REGION`   | AWS Default Region | `us-west-2`    | `us-west-1`   | No |
| `DATABASE_PATH` | Path of database to be backed up (within the container)   | `/myvolume/mydb.db` | None   | Yes |
| `BACKUP_PATH` | Path to write the backup (within the container)  | `/myvolume/mybackup.db` | `${DATABASE_PATH}.bak`   | No |
| `S3_ENDPOINT` | URL to S3-compatible endpoint (MinIO, Cloudflare R2, Wasabi) | `https://play.minio.com:9000` | None | No |
| `SQLITE_TIMEOUT_MS` | Busy timeout used by SQLite `.backup`/`.restore` (milliseconds) | `10000` | `10000` | No |
| `SCHEDULE` | Cron expression for scheduled backups | `0 1 * * *` | None | No (runs immediately if unset) |
| `LOG_LEVEL` | Verbosity of logs (`info` or `debug`) | `debug` | `info` | No |
| `POST_WEBHOOK_URL` | URL to call with a POST after successful backup | `https://example.com/hook` | None | No |
| `ENCRYPTION_KEY` | If set, encrypt backups before upload. Required to restore encrypted backups. | `your-strong-passphrase` | None | No (required to restore encrypted backups) |


## Docker Compose

You can run this container as a sidecar alongside your application and have it back up the SQLite database on a schedule, and trigger restores when needed.

### Backup sidecar (scheduled)

```yaml

volumes:
  app-data:

services:
  app:
    image: your-app-image:latest
    volumes:
      - app-data:/data # sqlite.db could live here.

  sqlite-backup:
    image: ghcr.io/le-lenn/docker-sqlite-to-s3:latest
    # Mount the same volume as the app, read-only is sufficient for backup
    volumes:
      - app-data:/data:ro
    environment:
      DATABASE_PATH: /data/sqlite3.db
      SCHEDULE: "0 1 * * *" # Run on a daily schedule at 1am (controlled via SCHEDULE)
      S3_BUCKET: your-bucket
      S3_PREFIX: backups/sqlite/
      AWS_ACCESS_KEY_ID: your-access-key
      AWS_SECRET_ACCESS_KEY: your-secret-key
      AWS_DEFAULT_REGION: us-west-2
      # Optional: if using an S3-compatible provider (MinIO, Cloudflare R2, Wasabi, Hetzner)
      # S3_ENDPOINT: https://your-provider-endpoint
      # Optional: tune backup/restore busy timeout (ms), default 10000
      # SQLITE_TIMEOUT_MS: 10000
      # Optional: notify another service when a backup completes
      # POST_WEBHOOK_URL: https://example.com/myhook
      # Optional: set if your DB is not at the default path
      # DATABASE_PATH: /data/yourdb.sqlite
      # Optional: encrypt backups before upload
      # ENCRYPTION_KEY: your-strong-passphrase
      # LOG_LEVEL=info
    restart: unless-stopped
    depends_on:
      - app
```

Test your backup configuration by triggering a manual backup with:
```sh
docker exec <backup container name> sh backup.sh
```

## Restore
> [!CAUTION]
> DATA LOSS! All database objects will be dropped and re-created.

### ... from latest backup

Stop the container using the sqlite db, then run restore.

```sh
docker exec <backup container name> sh restore.sh
```

> [!NOTE]
> If your bucket has more than a 1000 files, the latest may not be restored -- only one S3 `ls` command is used

### ... from specific backup

Stop the container using the sqlite db, then run restore.

```sh
docker exec <backup container name> sh restore.sh <timestamp>
```
