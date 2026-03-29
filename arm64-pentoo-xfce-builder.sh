#!/usr/bin/env bash
# arm64-pentoo-xfce-builder.sh
# One-script-to-rule-them-all: XFCE ARM64 ISO → Stage4 Gentoo tarball
# Includes fchroot customization, binhost, pentoo overlay, firstboot grow
set -euo pipefail

# -----------------------------
# Variables
# -----------------------------
ARCH=${1:-arm64}                   # arm64, amd64, x86
DATETIME=$(date +%Y%m%dT%H%M%S)
WORKDIR="$HOME/gains-${ARCH}"
TMPDIR=$(mktemp -d -p "$HOME" gains-iso-XXXX)
ISO_MNT="$TMPDIR/iso"
ROOT_TMP="$TMPDIR/root"
STAGE4_OUT="$HOME/pentoo-arm64-xfce-${DATETIME}.tar.xz"

# Seed ISO URL (official XFCE minimal ISO)
ISO_URL="https://distfiles.gentoo.org/releases/arm64/autobuilds/20260327T140102Z/install-arm64-minimal-20260327T140102Z.iso"
ISO_PATH="$TMPDIR/seed.iso"

# USE flags
USE_FLAGS="X wayland vulkan opencl dri udev elogind elogind-pam pam xfce desktop gnome-desktop"
VIDEO_USE="video_cards_vc4 video_cards_v3d video_cards_panfrost video_cards_panthor \
video_cards_nouveau video_cards_nvidia video_cards_amdgpu video_cards_radeonsi video_cards_radeon"
USE_FLAGS="${USE_FLAGS} ${VIDEO_USE}"

# Packages
PACKAGES="xfce4-base xorg-drivers x11-base/xorg-server x11-misc/xorg-drivers \
gnome-disks gparted parted nm-applet avahi firefox-bin easyeffects catalyst ashi zinc"

# -----------------------------
# Step 1: Download ISO
# -----------------------------
echo "[INFO] Downloading XFCE ARM64 ISO..."
wget -q --show-progress -O "$ISO_PATH" "$ISO_URL"

# -----------------------------
# Step 2: Mount and unsquash ISO
# -----------------------------
mkdir -p "$ISO_MNT" "$ROOT_TMP"
sudo mount -o loop "$ISO_PATH" "$ISO_MNT"
echo "[INFO] Extracting squashfs..."
sudo unsquashfs -d "$ROOT_TMP" "$ISO_MNT"/*.squashfs
sudo umount "$ISO_MNT"

# Copy resolv.conf for networking inside fchroot
sudo cp /etc/resolv.conf "$ROOT_TMP/etc/resolv.conf"

# -----------------------------
# Step 3: fchroot customization
# -----------------------------
echo "[INFO] Entering fchroot..."
fchroot "$ROOT_TMP" /bin/bash <<'EOF_CHROOT'
set -e

# -----------------------------
# Temporary users & passwords
# -----------------------------
echo "root:pleasechangeme10" | chpasswd
useradd -m -G wheel,video,audio gentoo
echo "gentoo:pleasechangeme10" | chpasswd

# -----------------------------
# Post-sync keywords automation
# -----------------------------
curl -sL https://raw.githubusercontent.com/necrose99/gentoo-config/refs/heads/master/scripts/post-sync-keyword.sh | bash

# -----------------------------
# GPU USE flags & package.use
# -----------------------------
mkdir -p /etc/portage/package.use/
wget -q -O /etc/portage/package.use/00-arm64-video_cards \
    https://raw.githubusercontent.com/necrose99/gentoo-config/refs/heads/master/package.use/00-arm64-video_cards

# -----------------------------
# Update grub wrapper
# -----------------------------
curl -sL https://raw.githubusercontent.com/necrose99/gentoo-config/refs/heads/master/scripts/setup-update-grub.sh | bash

# -----------------------------
# Install XFCE tools & packages
# -----------------------------
emerge -v --noreplace xfce4-base gnome-disks gparted parted nm-applet avahi firefox-bin easyeffects catalyst ashi zinc || true

# -----------------------------
# Swap stub (1MiB, grow later)
# -----------------------------
mkdir -p /swap
fallocate -l 1M /swap/swap.img
chmod 600 /swap/swap.img
echo "/swap/swap.img none swap defaults 0 0" >> /etc/fstab

# -----------------------------
# Firstboot root & swap grow script
# -----------------------------
cat << 'EOF_GROW' > /etc/init.d/firstboot-grow.sh
#!/usr/bin/env bash
set -e
echo "[INFO] Firstboot root & swap auto-grow"
btrfs filesystem resize max /
MAX_SWAP=16G
fallocate -l "$MAX_SWAP" /swap/swap.img
chmod 600 /swap/swap.img
mkswap /swap/swap.img
swapon /swap/swap.img
rm -f /etc/init.d/firstboot-grow.sh
EOF_GROW
chmod +x /etc/init.d/firstboot-grow.sh
EOF_CHROOT

# -----------------------------
# Step 4: Setup Gentoo binhost
# -----------------------------
sudo mkdir -p /etc/portage/binrepos.conf
cat << 'EOF_BINHOST' | sudo tee /etc/portage/binrepos.conf/gentoobinhostarm64.conf
[gentoo]
priority = 9999
sync-uri = https://mirrors.aliyun.com/gentoo/releases/arm64/binpackages/23.0/arm64
verify-signature = true
location = /var/cache/binhost/gentoo
EOF_BINHOST

# -----------------------------
# Step 5: Chymeric overlay & mkstage4
# -----------------------------
sudo mkdir -p /etc/portage/repos.conf
if [[ ! -f /etc/portage/repos.conf/chymeric.conf ]]; then
    sudo wget -q -O /etc/portage/repos.conf/chymeric.conf \
        https://raw.githubusercontent.com/TheChymera/overlay/master/metadata/chymeric.conf
fi

sudo emerge --sync >/dev/null
sudo emerge -q app-backup/mkstage4

# -----------------------------
# Step 6: Build Stage4 tarball
# -----------------------------
echo "[INFO] Creating Stage4 tarball..."
sudo mkstage4.sh -b -c -k -l -C xz -t "$ROOT_TMP" "$STAGE4_OUT"

echo "[INFO] DONE"
echo "Stage4 tarball ready: $STAGE4_OUT"
