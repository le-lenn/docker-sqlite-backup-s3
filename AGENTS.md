# Repository Guidelines

## Project Structure & Module Organization
- `src/`: POSIX shell scripts (`run.sh`, `backup.sh`, `restore.sh`, `env.sh`, `install.sh`).
- `Dockerfile`: Alpine image; installs `sqlite`, `aws-cli`, `openssl`, `go-cron`; entrypoint `run.sh`.
- `docker-compose-test.yml`: Local integration test stack with MinIO.
- `.github/workflows/`: CI builds multi-arch images to GHCR.
- `README.md`: Configuration samples and usage.

## Build, Test, and Development Commands
- Build image: `docker build -t ghcr.io/<owner>/<repo>:local .`
- Run test stack: `docker compose -f docker-compose-test.yml up --build`
- Trigger backup: `docker exec sqlite-backup sh /usr/src/backup.sh`
- Restore latest: `docker exec sqlite-backup sh /usr/src/restore.sh`
- Restore specific: `docker exec sqlite-backup sh /usr/src/restore.sh 2024_12_01_0100`

## Coding Style & Naming Conventions
- Scripts: POSIX `sh` only; use `set -eu -o pipefail`.
- Indentation: 2 spaces; no tabs.
- Variables: environment `UPPER_SNAKE_CASE` (`S3_BUCKET`, `AWS_DEFAULT_REGION`); locals `lower_snake_case`.
- Functions: `lower_snake_case` (e.g., `log_debug`).
- Prefer fail-fast checks and clear `echo` messages.
- Optional: lint with `shellcheck` and format with `shfmt` (if installed).

## Testing Guidelines
- Use `docker-compose-test.yml` to exercise backup/restore against MinIO.
- Verify objects appear under `readeck-backups/backups/sqlite/`.
- Test both encrypted (`ENCRYPTION_KEY` set) and unencrypted paths.
- No formal coverage targets; validate happy path and common failures (missing DB, bad creds).

## Commit & Pull Request Guidelines
- Commit messages: short, imperative (e.g., "Refine README", "Abort when db missing").
- PRs: include summary, configuration/env changes, test steps/commands, sample logs, and linked issues.
- Update `README.md` when environment variables or usage change.

## Security & Configuration Tips
- Never commit credentials; inject via environment or secrets.
- Use `LOG_LEVEL=debug` only for troubleshooting; avoid leaking secrets.
- Keep `ENCRYPTION_KEY` secure; it is required to restore encrypted backups.
