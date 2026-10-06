sudo apt install ansible
ansible-playbook -K newInstall.yml

# nas.yml uses community.general modules (zfs, snap, ufw) — install once:
ansible-galaxy collection install -r requirements.yml

ansible-playbook -vvv -i inventory.yml -l nas nas.yml --ask-become-pass

## Bonus drift report (nas.yml vs live bonus, 2026-10-05)

nas.yml was rewritten to match the live state of bonus (Ubuntu 24.04.5, kernel
7.0.0-34-generic HWE-edge). Differences found and folded in:

### Network / NFS
- NEW (2026-10-06): bond topology now managed by ansible (tag: network).
  Physical NICs -> bond0 (active-backup, primary enp2s0, mii-monitor 100ms)
  -> br0 (bridge, DHCP metric 100). Template: files/netplan.yaml.j2.
  ALL FIVE installer NIC names are bond slaves (enp2s0, enp8s0, enp49s0,
  enp87s0, enp88s0) — four are BIOS-disabled for power testing today.
  systemd-networkd tolerates absent NICs (the installer already ships
  waiting .network files for them), so re-enabling any NIC in BIOS + reboot
  auto-enslaves it into bond0 with NO OS reconfiguration.
  `netplan apply` is tagged never-run-automatically (SSH blip risk; prefer
  `sudo netplan try` on a live box). Installer 50-cloud-init.yaml is removed
  (it would override our config; cloud-init is already disabled on the box).
  Verified with `netplan generate`: clean parse, bond0.netdev gets
  Mode=active-backup MIIMonitorSec=100ms PrimaryReselectPolicy=always,
  enp2s0 gets PrimarySlave=true, all 5 NICs get Bond=bond0 files.
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
- CHANGED 2026-10-06: docker-ce replaced by PODMAN (tag: podman).
  Playbook installs podman 4.9.x + podman-compose + netavark/aardvark-dns
  from noble universe (no upstream repo) and asserts docker-ce ABSENT.
  podman.socket enabled for docker-API compat. Live plex/ARM containers
  migrate at the 26.04 reinstall (see RECOVERY.md step 3); do NOT run
  --tags podman against the live box before then (it removes docker under
  the running containers).
- LXD snap 5.21/stable + zfs storage pool `fast` (source=fast/lxd).
  NEW: default profile eth0 pinned to parent=br0 (bond-backed) by ansible.
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
  Re-synced 2026-10-06: live equivalents are `rng-tools-debian` and
  `libncurses-dev` — both now in the playbook.

### Package re-sync (2026-10-06, apt-mark showmanual vs nas.yml)
Diffed the 119 user-selected (manual) packages on live bonus against the
playbook. 48 missing user-selected packages added in six grouped tasks
(dev/packaging, tracing/debug, media, storage/recovery, VCS, kernel metas):
- dev/packaging: ansible, ansible-lint, build-essential, autoconf,
  autotools-dev, bison, debhelper, devscripts, dh-autoreconf,
  dh-translations, fakeroot, gobject-introspection, libdw-dev,
  libncurses-dev, manpages-dev, pbuilder-scripts, sbuild,
  ubuntu-dev-tools, texinfo, texi2html, texlive-fonts-recommended,
  texlive-latex-base, python3-full
- tracing/debug: bpftrace, elfutils, fatrace, perf-tools-unstable, sysstat,
  i2c-tools, cscope, jq, tinymembench
- media: ffmpeg, ghostscript, mediainfo
- storage/recovery: 7zip, exfatprogs, gddrescue, myrescue, nvme-cli,
  testdisk, lsscsi, rng-tools-debian
- VCS: git-email, gitk
- kernel metas: linux-generic (GA, manual on live alongside HWE-edge),
  linux-tools-generic-7.0, linux-tools-generic-hwe-24.04

Intentionally NOT added (base-system / boot-chain / already covered):
bash, dash, mawk, grep, gzip, diffutils, findutils, hostname, login,
libc-bin, bsdutils, util-linux, debianutils, ncurses-base, ncurses-bin,
ca-certificates, curl, git, fwupd, efibootmgr, grub-efi-amd64(-signed),
shim-signed, ubuntu-minimal, ubuntu-standard, ubuntu-server-minimal —
all pulled in by the Ubuntu base seed on any install. led-ugreen-dkms /
led-ugreen-utils are manual on live but installed by the leds deb task.
linux-tools-7.0.0-31-generic is a versioned leftover (superseded by the
-34 kernel + tools metas).

### dpkg conffile audit (authoritative, 2026-10-05)
Diffed every conffile md5 in /var/lib/dpkg/status against the live files across
1,786 packages. Result: only ONE modified package conffile:
- /etc/hdparm.conf (our spin-down config — already managed).
Everything else custom in /etc is admin-added (unowned by any package).
Notable unowned files now captured by the playbook:
- /etc/modprobe.d/{zfs,i915,r8127,drm-poll}.conf
- /etc/modules-load.d/ugreen-led.conf, /etc/ugreen-leds.conf
- /etc/exports, /etc/fail2ban/jail.local, /etc/samba/smb.conf [z] block
- /etc/apt/sources.list.d/docker.list + keyrings/docker.asc
- /etc/ssh/sshd_config edits, authorized_keys
Notable unowned files intentionally NOT managed (installer/system artifacts):
- /etc/cloud/cloud.cfg.d/* — installer artifacts; note /etc/cloud/cloud-init.disabled
  is present (installer disabled cloud-init after first boot). Leave as-is.
- /etc/default/grub — one drift of note: GRUB_CMDLINE_LINUX_DEFAULT was
  "pcie_aspm=force" at install (see grub.ucf-dist), later reverted to "".
  ASPM is instead enabled per-driver via r8127.conf (aspm=1). If reinstalling,
  do NOT re-add pcie_aspm=force globally.
- /etc/hosts.allow, /etc/hosts.deny — empty of rules (all comments).
- passwd/shadow/group/machine-id/zpool.cache/console-setup caches — system state.

### Manual steps after a fresh run
1. `sudo canonical-livepatch enable <token>` (from ubuntu.com/advantage).
2. `lxd init` if not preseeded, then the storage task creates pool `fast`.
3. `smbpasswd -a chiluk` for the [z] share.
4. Verify by-id disk paths before running the `never-run-automatically` tagged
   fast-pool creation task (skip with --skip-tags never-run-automatically).
5. rsnapshot cron entries in newInstall.yml reference weekly/monthly but
   /etc/rsnapshot.conf only defines alpha/beta/gamma — reconcile before use.
