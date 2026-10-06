sudo apt install ansible
ansible-playbook -K newInstall.yml

# nas.yml uses community.general modules (zfs, snap, ufw) — install once:
ansible-galaxy collection install -r requirements.yml

ansible-playbook -vvv -i inventory.yml -l nas nas.yml --ask-become-pass

## Bonus drift report (nas.yml vs live bonus, 2026-10-05)

nas.yml was rewritten to match the live state of bonus (Ubuntu 24.04.5, kernel
7.0.0-34-generic HWE-edge). Differences found and folded in:

### Network / NFS
- LAN moved 192.168.1.1/24 -> 192.168.0.1/16 (files/exports updated).
- NFS export gained `crossmnt` (so z/backup shows under /z for v4 clients).
- /etc/nfs.conf: `[mountd] manage-gids=y` (new task).
- bonus sits on bridge `br0` (member enp2s0, DHCP, STP on) — created by
  netplan at install; netplan file is root-only, not managed by ansible yet.
  If reinstalling, replicate: br0 with enp2s0 enslaved, DHCP on br0.

### ZFS (biggest drift — original nas.yml only imported z + atime=off)
- z pool now has: special vdev (mirror 2x 990 PRO part1), ZIL (mirror 2x 990
  PRO part2), L2ARC (2x 990 PRO part3).
- z props: atime=off, recordsize=1M, special_small_blocks=32K.
- NEW pool `fast` = mirror of 2x 990 PRO part4, ashift=12, recordsize=1M;
  hosts LXD storage `fast/lxd` (containers live there now — hermes).
- /etc/modprobe.d/zfs.conf: `options zfs l2arc_rebuild_enabled=1`.
- zfs-trim-weekly@z.timer, zfs-trim-weekly@fast.timer, fstrim.timer enabled.
- Scrub left to packaged /etc/cron.d/zfsutils-linux.

### Services added since original yaml (all enabled on live box)
- samba: [z] share (rw, valid users chiluk) + smbd/nmbd.
- docker-ce 29.x from download.docker.com repo (key /etc/apt/keyrings/docker.asc).
- LXD snap 5.21/stable + zfs storage pool `fast` (source=fast/lxd).
- atop, pcp (pmcd/pmlogger), schroot, unattended-upgrades, thermald.
- canonical-livepatch snap installed but NOT enabled (needs token).

### UGREEN LEDs (DXP chassis; nothing in old yaml)
- led-ugreen dkms kmod (miskcoo/ugreen_leds_controller) + led-ugreen-utils deb.
- /etc/modules-load.d/ugreen-led.conf: i2c-dev, led-ugreen, ledtrig-oneshot,
  ledtrig-netdev.
- ugreen-diskiomon / probe-leds / netdevmon services DISABLED on live box —
  diskiomon hammers i801 SMBus ~25/s and blocks s0ix. Playbook keeps them off.

### Power tuning (new)
- /etc/modprobe.d/i915.conf: enable_dc=2, disable_power_well=1,
  enable_guc=3 enable_fbc=1, xe guc_log_level=0.
- intel_lpmd + thermald enabled.

### Kernel
- HWE edge meta-package `linux-generic-hwe-24.04-edge` (running 7.0.0-34).
  Original yaml installed no kernel meta — reinstalls would stay on GA 6.8.

### Security
- sshd PermitRootLogin no / PasswordAuthentication no: unchanged, still true.
- jail.local is byte-identical to live (md5 39c171cf...). sshd jail comes from
  Ubuntu's packaged jail.d/defaults-debian.conf (nftables + systemd backend).
- ufw installed but ENABLED=no (playbook asserts disabled to match).
- chiluk authorized_keys captured to files/authorized_keys_chiluk
  (4 keys: dchiluk@indeed.com, 2x lp:chiluk, herby@chiluk.com).

### Dropped from original list (not on live box)
- rng-tools (removed at some point), libncurses5-dev (never on noble).

### Manual steps after a fresh run
1. `sudo canonical-livepatch enable <token>` (from ubuntu.com/advantage).
2. `lxd init` if not preseeded, then the storage task creates pool `fast`.
3. `smbpasswd -a chiluk` for the [z] share.
4. Verify by-id disk paths before running the `never-run-automatically` tagged
   fast-pool creation task (skip with --skip-tags never-run-automatically).
5. rsnapshot cron entries in newInstall.yml reference weekly/monthly but
   /etc/rsnapshot.conf only defines alpha/beta/gamma — reconcile before use.
