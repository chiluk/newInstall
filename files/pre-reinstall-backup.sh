#!/bin/bash
# pre-reinstall backup for bonus — run ON BONUS before wiping the root disk.
# Everything persistent lives on the z pool (3x raidz1 HDDs, separate from the
# root SSD), so the OS reinstall does NOT touch it. This script consolidates the
# things that DO live on the root disk (docker images, ollama models) onto z,
# and exports the hermes LXD container.
#
# Usage:  ./pre-reinstall-backup.sh [dest-root]   (default /z/backup/reinstall)
set -euo pipefail

DEST="${1:-/z/backup/reinstall-$(date +%Y%m%d)}"
mkdir -p "$DEST"
echo "Backup destination: $DEST"

# ---------------------------------------------------------------- LXD hermes
# lxc export requires the instance stopped. Takes ~23G (fast pool).
echo ">>> Exporting LXD container 'hermes' (will stop/start it)"
lxc stop hermes --timeout 60
lxc export hermes "$DEST/hermes.tar.gz" --optimized-storage --instance-only
lxc start hermes

# capture LXD config (tiny, but recreates pool/profile/server settings exactly)
lxc config show            > "$DEST/lxd-server-config.yaml"
lxc profile show default   > "$DEST/lxd-profile-default.yaml"
lxc storage show fast      > "$DEST/lxd-storage-fast.yaml"

# ---------------------------------------------------------------- docker images
# /var/lib/docker is on the ROOT disk — all images die on reinstall.
# Public images re-pull; CUSTOM ones must be saved or they are gone forever.
echo ">>> Saving custom docker images (no Dockerfile exists on this box)"
docker save ipex_llm_chiluk:latest  -o "$DEST/ipex_llm_chiluk.tar"   # ~20G
docker save bookworm-build:latest    -o "$DEST/bookworm-build.tar"    # ~700M (optional)

# ---------------------------------------------------------------- ollama models
# 8G of models on root disk (/home/chiluk/.ollama) -> move onto z.
echo ">>> Copying ollama models to /z/ollama"
rsync -aHAX --info=progress2 /home/chiluk/.ollama/ /z/ollama/

# ---------------------------------------------------------------- checksums
echo ">>> Checksumming"
(cd "$DEST" && sha256sum *.tar.gz *.tar > SHA256SUMS.txt)

echo
echo "Done. Contents:"
ls -lh "$DEST"
echo
echo "STRONGLY recommended: copy $DEST to another host (beast/hermes) before wiping:"
echo "  rsync -aHAX --info=progress2 $DEST/ user@beast:/path/off-box-backup/"
