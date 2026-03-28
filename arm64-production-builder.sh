#!/usr/bin/env bash
# arm64-production-builder.sh
# One script to build ARM64 system: Stage4 tarball + optional raw disk image
set -euo pipefail

# -----------------------------
# Variables
# -----------------------------
ARCH="arm64"
DATETIME=$(date +%Y%m%dT%H%M%S)
BASE_URL="https://distfiles.gentoo.org/releases"
WORKDIR="$HOME/${ARCH}"
TMPDIR=$(mktemp -d -p "$HOME" gentoo-arm64-iso-XXXX)
ISO_MNT="$TMPDIR/iso"
ROOT_TMP="$TMPDIR/root"
STAGE4_OUT="$HOME/sqashfs2stage4gentoo-${ARCH}-${DATETIME}.tar.xz"

# Raw image options
BUILD_IMG=${1:-true}     # pass false to skip raw image creation
IMG_OUT="$HOME/arm64-system-${DATETIME}.img"
IMG_SIZE="16G"
EFI_SIZE="120M"
BOOT_SIZE="550M"
ROOT_SIZE="2G"           # initial BTRFS root size
SWAP_MIN="1M"
SWAP_MAX="16G"

TOOLS=("xfce4-base" "gnome-disks" "gparted" "parted" "catalyst" "ashi" "vulkan" "zinc")

# -----------------------------
# Fetch latest ARM64 ISO
# -----------------------------
echo "[INFO] Detecting latest ISO for $ARCH..."
ISO_REL=$(curl -s "${BASE_URL}/${ARCH}/autobuilds/" \
    | grep -oP 'href=".*?\.iso"' \
    | grep -v -i "CHECKSUM" \
    | sed 's/href="//;s/"//' \
    | sort | tail -n1)

if [[ -z "$ISO_REL" ]]; then
    echo "[ERROR] Could not find ISO for $ARCH"
    exit 1
fi

ISO_URL="${BASE_URL}/${ARCH}/autobuilds/${ISO_REL}"
ISO_PATH="$TMPDIR/$ISO_REL"

echo "[INFO] Downloading ISO: $ISO_URL"
wget -q --show-progress -O "$ISO_PATH" "$ISO_URL"

# -----------------------------
# Mount + extract squashfs
# -----------------------------
mkdir -p "$ISO_MNT" "$ROOT_TMP"
sudo mount -o loop "$ISO_PATH" "$ISO_MNT"
echo "[INFO] Extracting squashfs..."
sudo unsquashfs -d "$ROOT_TMP" "$ISO_MNT"/*.squashfs
sudo umount "$ISO_MNT"

# -----------------------------
# fchroot customizations
# -----------------------------
echo "[INFO] Preparing fchroot environment..."
sudo cp /etc/resolv.conf "$ROOT_TMP/etc/resolv.conf"

fchroot "$ROOT_TMP" /bin/bash <<'EOF_CHROOT'
set -e

# -----------------------------
# Post-sync keyword automation
# -----------------------------
curl -sL https://raw.githubusercontent.com/necrose99/gentoo-config/refs/heads/master/scripts/post-sync-keyword.sh | bash

# -----------------------------
# GPU USE flags for ARM64
# -----------------------------
mkdir -p /etc/portage/package.use/
wget -q -O /etc/portage/package.use/00-arm64-video_cards \
    https://raw.githubusercontent.com/necrose99/gentoo-config/refs/heads/master/package.use/00-arm64-video_cards

# -----------------------------
# Update GRUB wrapper
# -----------------------------
curl -sL https://raw.githubusercontent.com/necrose99/gentoo-config/refs/heads/master/scripts/setup-update-grub.sh | bash
# -----------------------------
# Add Gains 
# -----------------------------
GITLAB_URL="https://gitlab.com/yourusername/gains/-/archive/main/gains-main.tar.gz"
TMP_GIT="$TMPDIR/gains-main.tar.gz"

wget -q --show-progress -O "$TMP_GIT" "$GITLAB_URL"
tar -xzf "$TMP_GIT" -C "$TMPDIR"
GIT_DIR="$TMPDIR/gains-main"
# -----------------------------
# Install XFCE + tools
# -----------------------------
emerge -v --noreplace xfce4-base gnome-disks gparted parted catalyst ashi vulkan zinc || true
# -----------------------------
# Source temporary password snippet
# -----------------------------
if [[ -f /tmp/dopass.sh ]]; then
    source /tmp/dopass.sh
else
    echo "[WARN] /tmp/dopass.sh not found, skipping temp password setup"
fi
# -----------------------------
# Swap stub (1MiB, grows later)
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
echo "[INFO] First-boot root & swap auto-grow"

# Grow BTRFS root
btrfs filesystem resize max /

# Grow swap.img
MAX_SWAP=16G
fallocate -l "$MAX_SWAP" /swap/swap.img
chmod 600 /swap/swap.img
mkswap /swap/swap.img
swapon /swap/swap.img

# Remove self
rm -f /etc/init.d/firstboot-grow.sh
EOF_GROW

chmod +x /etc/init.d/firstboot-grow.sh
EOF_CHROOT

# -----------------------------
# Gentoo ARM64 binhost
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
# Chymeric overlay + mkstage4
# -----------------------------
sudo mkdir -p /etc/portage/repos.conf
if [[ ! -f /etc/portage/repos.conf/chymeric.conf ]]; then
    sudo wget -q -O /etc/portage/repos.conf/chymeric.conf \
        https://raw.githubusercontent.com/TheChymera/overlay/master/metadata/chymeric.conf
fi
sudo emerge --sync >/dev/null
sudo emerge -q app-backup/mkstage4

# -----------------------------
# Build Stage4 tarball
# -----------------------------
echo "[INFO] Creating Stage4 tarball: $STAGE4_OUT"
sudo mkstage4.sh -b -c -k -l -C xz -t "$ROOT_TMP" "$STAGE4_OUT"
echo "[INFO] Stage4 tarball ready: $STAGE4_OUT"

# -----------------------------
# Optional: Build raw image
# -----------------------------
if [ "$BUILD_IMG" = true ]; then
    echo "[INFO] Building raw ARM64 image: $IMG_OUT"
    fallocate -l "$IMG_SIZE" "$IMG_OUT"
    parted "$IMG_OUT" --script mklabel gpt
    parted "$IMG_OUT" --script mkpart ESP fat32 1MiB "$EFI_SIZE"
    parted "$IMG_OUT" --script mkpart BOOT ext4 "$EFI_SIZE" "$((EFI_SIZE+BOOT_SIZE))M"
    parted "$IMG_OUT" --script mkpart ROOT btrfs "$((EFI_SIZE+BOOT_SIZE))M" 100%
    LOOP_DEV=$(losetup --show -fP "$IMG_OUT")
    EFI_PART="${LOOP_DEV}p1"
    BOOT_PART="${LOOP_DEV}p2"
    ROOT_PART="${LOOP_DEV}p3"

    mkfs.vfat "$EFI_PART"
    mkfs.ext4 "$BOOT_PART"
    mkfs.btrfs -f "$ROOT_PART"

    # Optionally populate ROOT_PART with Stage4
    sudo mount "$ROOT_PART" /mnt
    sudo tar --numeric-owner -xJf "$STAGE4_OUT" -C /mnt
    sudo umount /mnt
    losetup -d "$LOOP_DEV"
    echo "[INFO] Raw image ready: $IMG_OUT"
fi

echo "[INFO] All done ✅"
