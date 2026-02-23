# Stop, backup, and restore (no volume delete)

## Stop n8n and keep all data

```bash
cd local-n8n-setup
docker compose down
```

**Do not** use `docker compose down -v` — that removes volumes and deletes data.

---

## Start again (same state)

```bash
docker compose up -d
```

Volumes are preserved, so your workflows, credentials, and owner account stay.

---

## Backup volumes into this project (optional)

Run while the stack is up so Postgres can be dumped:

```bash
cd local-n8n-setup
./backup-volumes.sh
```

Creates:

- `backups/n8n_db_YYYYMMDD_HHMMSS.sql` — Postgres dump
- `backups/n8n_data_YYYYMMDD_HHMMSS.tar.gz` — n8n config + encryption key

Backups live in `local-n8n-setup/backups/` (ignored by git).

---

## Restore after accidental `docker compose down -v`

Use this when you ran `-v` by mistake and lost the volumes. You need a backup made earlier with `./backup-volumes.sh`. Pick **one timestamp** (e.g. `20250223_143000`) and use it for both the SQL and the tar.gz file.

### Step 1 — Bring up fresh (empty) volumes

```bash
cd local-n8n-setup
docker compose up -d
```

Wait ~15 seconds for Postgres to be ready.

### Step 2 — Restore Postgres (DB dump)

```bash
docker compose exec -T postgres psql -U postgres n8n < backups/n8n_db_YYYYMMDD_HHMMSS.sql
```

Use your real backup filename, e.g. `n8n_db_20250223_143000.sql`.

### Step 3 — Stop n8n

```bash
docker compose stop n8n
```

### Step 4 — Restore n8n_data (config, encryption key, etc.)

```bash
docker run --rm -v local-n8n-setup_n8n_data:/data -v "$(pwd)/backups:/backup" alpine sh -c "cd /data && tar xzf /backup/n8n_data_YYYYMMDD_HHMMSS.tar.gz"
```

Use the **same timestamp** as the SQL file, e.g. `n8n_data_20250223_143000.tar.gz`.

### Step 5 — Start n8n again

```bash
docker compose start n8n
```

### Step 6 — Keep .env in sync

Your restored `n8n_data` contains the encryption key that was in use when you backed up. Ensure `N8N_ENCRYPTION_KEY` in `.env` matches that (or n8n will crash with “Mismatching encryption keys”). If you never changed the key, you’re fine.

---

## What each restore command does (breakdown)

### 1. `cd local-n8n-setup` and `docker compose up -d` (wait ~15 s)

| Part | What it does |
|------|----------------|
| `cd local-n8n-setup` | Go into the folder that has `docker-compose.yml` so the next commands run in the right place. |
| `docker compose up -d` | Start the stack in the background: create and start the **postgres** and **n8n** containers. Because the volumes were removed by `-v`, Docker creates **new empty** volumes and attaches them. Postgres initializes an empty database; n8n will start against that empty DB. |
| Wait ~15 s | Postgres needs a few seconds to be ready to accept connections. The n8n container waits for Postgres (healthcheck), but for the next step (restore SQL) you want Postgres fully up. |

**Result:** Running stack with empty Postgres DB and empty n8n_data volume.

---

### 2. `docker compose exec -T postgres psql -U postgres n8n < backups/n8n_db_YYYYMMDD_HHMMSS.sql`

| Part | What it does |
|------|----------------|
| `docker compose exec` | Run a command **inside** an already-running container that belongs to this compose project. |
| `-T` | Don’t allocate a TTY (no interactive terminal). Needed when input is coming from a file or pipe so `psql` doesn’t expect keyboard input. |
| `postgres` | The **service name** from `docker-compose.yml` (the Postgres container). |
| `psql -U postgres n8n` | Run the Postgres client: connect as user `postgres` to the database named `n8n`. |
| `< backups/n8n_db_YYYYMMDD_HHMMSS.sql` | Send the contents of that file **into** `psql` as input. So all the SQL statements in the backup file (CREATE TABLE, INSERT, etc.) run inside the `n8n` database. |

**Result:** The `n8n` database in the running Postgres container is repopulated with your backed-up data (users, workflows, credentials, etc.).

---

### 3. `docker compose stop n8n`

| Part | What it does |
|------|----------------|
| `docker compose stop n8n` | Stop only the **n8n** container. Postgres keeps running. We stop n8n so it isn’t writing to the `n8n_data` volume while we overwrite that volume with the backup. |

**Result:** n8n is stopped; Postgres is still running; the `n8n_data` volume is no longer in use by n8n.

---

### 4. `docker run --rm -v local-n8n-setup_n8n_data:/data -v "$(pwd)/backups:/backup" alpine sh -c "cd /data && tar xzf /backup/n8n_data_YYYYMMDD_HHMMSS.tar.gz"`

| Part | What it does |
|------|----------------|
| `docker run` | Run a **one-off** container (not part of the compose stack). |
| `--rm` | Remove the container when it exits (no leftover container). |
| `-v local-n8n-setup_n8n_data:/data` | Mount the Docker volume named `local-n8n-setup_n8n_data` (the n8n data volume) at `/data` inside the container. So we can write files into that volume. |
| `-v "$(pwd)/backups:/backup"` | Mount your **host** folder `local-n8n-setup/backups` at `/backup` inside the container so the container can read the `.tar.gz` file. |
| `alpine` | Use the small Alpine Linux image (has `tar` and a shell). |
| `sh -c "..."` | Run a shell command inside the container. |
| `cd /data` | Change to the folder that is the n8n volume. |
| `tar xzf /backup/n8n_data_YYYYMMDD_HHMMSS.tar.gz` | **Extract** the backup: `x` = extract, `z` = gzip, `f` = file. So the contents of the backup tar.gz are written into `/data`, i.e. into the `n8n_data` volume (config, encryption key, etc.). |

**Result:** The `n8n_data` volume now contains the same files as at backup time (including the encryption key n8n expects).

---

### 5. `docker compose start n8n`

| Part | What it does |
|------|----------------|
| `docker compose start n8n` | Start the **n8n** container again (same container, not a new one). It reattaches to the same `n8n_data` volume, which we just restored. |

**Result:** n8n runs again, reads the restored config and encryption key from `n8n_data`, and connects to the restored Postgres DB. Your workflows, credentials, and owner account are back (as of the backup timestamp).
