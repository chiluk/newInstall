# Container recovery after reformatting bonus to 26.04

Inventory taken from live bonus 2026-10-05.

## What survives the reinstall automatically
Everything under the **z pool** (3x raidz1 HDDs) and **fast pool** (NVMe mirror)
survives as long as you *import* the pools rather than wipe them. The installer
only formats the root SSD (ext4, UUID 6682d5a7...). Do NOT let the installer
touch the HDDs or the 990 PRO NVMe partitions.

Survives: /z/plex, /z/arm, /z/containers/homeassistant, /z/ai/models,
z/backup, and (if you back it up first) the hermes LXD dataset on fast.

## What DIES with the root disk (back these up first)
1. **Custom docker images** — no Dockerfiles exist anywhere on the box:
   - `ipex_llm_chiluk:latest` (~20G, built 16 months ago from IPEX-LLM scripts)
   - `bookworm-build:latest` (~700M, pbuilder-style)
   `docker save` both. Public images (plex, HA, ARM, ollama) re-pull fine.
2. **Ollama models** — 8G in `/home/chiluk/.ollama` (root disk!).
   rsync to `/z/ollama` (compose file already updated to that path).
3. **Docker container definitions** — no compose files existed; reconstructed
   from `docker inspect` into `files/docker-compose.yml` (this repo).
4. **LXD hermes container** — 23.2G dataset `fast/lxd/containers/hermes`.
   `lxc export` it (script does this; stops/starts hermes ~1 min).
5. **LXD server/profile/storage config** — captured by the script to YAML.

## Recovery procedure (after 26.04 is installed)

### 1. Import the pools
    zpool import z
    zpool import fast
    zfs set atime=off z
    # verify: zfs list shows z, z/backup, fast, fast/lxd/*

### 2. Restore hermes (LXD)
    # install lxd snap 5.21/stable (nas.yml does this)
    lxd init --auto   # or preseed; then:
    zfs create -o canmount=off fast/lxd 2>/dev/null || true
    lxc storage create fast zfs source=fast/lxd
    lxc import /z/backup/reinstall*/hermes.tar.gz
    lxc config device add hermes eth0 nic nictype=bridged parent=br0  # if needed
    lxc start hermes
    # NOTE: import keeps the container's cloud-init instance-id — host keys stay
    # as they are now, no known_hosts churn beyond what you already accepted.
    # br0 must exist first (netplan: bridge with enp2s0, DHCP on br0).

### 3. Restore docker
    # install docker-ce (nas.yml does this)
    docker load -i /z/backup/reinstall*/ipex_llm_chiluk.tar
    docker load -i /z/backup/reinstall*/bookworm-build.tar   # optional
    cd /path/to/newInstall/files && docker compose up -d
    # ollama now reads models from /z/ollama (bind updated in compose file)

### 4. Verify
    docker ps                     # 5 containers
    lxc list                      # hermes RUNNING at 192.168.0.4
    # plex claim token is in compose env; HA/ARM configs all on /z.

## Gotchas found during the audit
- **homeassistant** live env had `TZ=MY_TIME_ZONE` (never set). Compose file
  fixes it to America/Chicago.
- **ollama** bind was on the root disk — the single biggest silent-loss risk.
  Fixed to /z/ollama in the compose file; backup script does the rsync.
- **ipex-llm-chiluk** uses `--shm-size 16g` and host networking; compose file
  preserves both. restart policy is `no` (manual-use container).
- **ARM** needs /dev/sr0 (the DVD drive) and runs privileged with UID/GID 1001.
- **plex** bind-mounts all of /z read-write into the container; keep that or
  library paths break.
- hermes uses `security.nesting: true` (docker-in-container) — preserved by
  lxc export/import automatically.
- 26.04 note: LXD 5.21 snap still runs on 26.04; if you adopt the new
  `lxd` deb (LXD 6.x / LXD Images), the import still works but the default
  remote changes — stick with the snap until hermes is migrated deliberately.

## Files in this repo
- files/docker-compose.yml        — reconstructed 5-container definition
- files/pre-reinstall-backup.sh  — run on bonus BEFORE wiping (lxc export,
                                   docker save, ollama rsync, checksums)
