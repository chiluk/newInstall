# Container recovery after reformatting bonus to 26.04

Inventory taken from live bonus 2026-10-05.
Updated 2026-10-05: user removed the stopped containers — homeassistant,
ollama, and ipex-llm-chiluk are gone. Only plex and ARM remain.

## What survives the reinstall automatically
Everything under the **z pool** (3x raidz1 HDDs) and **fast pool** (NVMe mirror)
survives as long as you *import* the pools rather than wipe them. The installer
only formats the root SSD (ext4, UUID 6682d5a7...). Do NOT let the installer
touch the HDDs or the 990 PRO NVMe partitions.

Survives: /z/plex, /z/arm, z/backup, and (if you back it up first) the
hermes LXD dataset on fast.

## Remaining containers (2)
    plex  plexinc/pms-docker        binds: /z/plex/config, /z/plex/transcode, /z:/z
                                   host net, /dev/dri, claim token in compose env
    ARM   automatic-ripping-machine binds: /z/arm/{logs,config}
                                   privileged, /dev/sr0, port 8080, UID/GID 1001

Both use PUBLIC images — they re-pull from Docker Hub after the reinstall.
All their state is bind-mounted on /z, so nothing else needs saving for them.

## What still dies with the root disk (decide before wiping)
1. **LXD hermes container** — 23.2G dataset `fast/lxd/containers/hermes`.
   `lxc export` it (backup script does this; stops/starts hermes ~1 min).
2. **LXD server/profile/storage config** — captured by the script to YAML.
3. **bookworm-build:latest** (~700M) — custom local image, no Dockerfile.
   Save if you still use the pbuilder env.
4. **Leftover unused images** — `ipex_llm_chiluk` (~20G) and
   `intelanalytics/ipex-llm-inference-cpp-xpu` (~22G) are still on the box
   but attached to no container. Either `docker save` them or let the
   reformat reclaim them.
5. **Ollama models** — container gone, but `/home/chiluk/.ollama` (8G) may
   still be on the root disk. Delete or move to /z if the models matter.
6. **Home Assistant config** — container gone; `/z/containers/homeassistant/config`
   remains on z. Delete whenever you like.

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

### 3. Restore containers (podman — migrated from docker 2026-10-06)
    # install podman + podman-compose (nas.yml does this; tag: podman)
    systemctl enable --now podman.socket
    podman load -i /z/backup/reinstall*/bookworm-build.tar   # optional
    cd /path/to/newInstall/files && podman-compose up -d
    # plex + ARM images pull from Docker Hub automatically
    # (compose file is unchanged — podman-compose is compatible)
    # NOTE: containers under podman-compose do NOT auto-start on boot by
    # default. Either enable podman-restart.service-style units or use:
    #   podman generate systemd --new --name plex -t 30 > /etc/systemd/system/plex.service
    # (repeat for ARM), then systemctl enable --now plex ARM.

### 4. Verify
    podman ps                     # plex + ARM
    lxc list                      # hermes RUNNING at 192.168.0.4
    # plex claim token is in compose env; ARM config on /z.

## Gotchas
- **ARM** needs /dev/sr0 (the DVD drive) and runs privileged with UID/GID 1001.
- **plex** bind-mounts all of /z read-write into the container; keep that or
  library paths break.
- hermes uses `security.nesting: true` (docker-in-container) — preserved by
  lxc export/import automatically.
- 26.04 note: LXD 5.21 snap still runs on 26.04; if you adopt the new
  `lxd` deb (LXD 6.x / LXD Images), the import still works but the default
  remote changes — stick with the snap until hermes is migrated deliberately.

## Files in this repo
- files/docker-compose.yml        — plex + ARM (reconstructed from docker inspect)
- files/pre-reinstall-backup.sh  — run on bonus BEFORE wiping (lxc export,
                                   bookworm-build save, checksums)
