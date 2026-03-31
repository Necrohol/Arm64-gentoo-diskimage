#!/bin/bash

# Define Portage paths
ENV_FILE="/etc/portage/env/efi-arch-logic"
PKG_ENV="/etc/portage/package.env"
KEYWORDS="/etc/portage/package.accept_keywords/efi-tools"

echo "Creating EFI architecture override environment..."

# Create the environment file that mimics the pkg_setup logic for ARM/RISC-V
# This ensures variables like EFIARCH are set correctly during the build phase
cat << 'EOF' > "$ENV_FILE"
pre_pkg_setup() {
    if use arm64; then
        export EFIARCH=aa64
        export BUILDARCH=aarch64
    elif use riscv; then
        export EFIARCH=riscv64
        export BUILDARCH=riscv64
    fi
    
    # Log the override for debugging
    einfo "Override: Setting EFIARCH=${EFIARCH} and BUILDARCH=${BUILDARCH}"
}
EOF

# Create Keyword overrides
echo "Unmasking tools for arm64 and riscv64..."
cat << EOF > "$KEYWORDS"
sys-boot/refind ~arm64
sys-boot/refind ~riscv
sys-boot/shim ~arm64
sys-boot/shim ~riscv
sys-boot/mokutil ~arm64
sys-boot/mokutil ~riscv
# uefi-mkconfig is stable on arm64, needs testing keyword for riscv64
sys-boot/uefi-mkconfig ~riscv
EOF

# Link packages to the environment override
echo "Linking packages to override logic..."
{
    echo "sys-boot/refind efi-arch-logic"
    echo "sys-boot/shim efi-arch-logic"
    echo "sys-boot/uefi-mkconfig efi-arch-logic"
} >> "$PKG_ENV"

echo "Done. Please run 'emerge --info sys-boot/refind' to verify variables."

# This function runs before the ebuild's own pkg_setup
pre_pkg_setup() {
    if use arm64; then
        export EFIARCH="aa64"
        export BUILDARCH="aarch64"
    elif use riscv; then
        export EFIARCH="riscv64"
        export BUILDARCH="riscv64"
    fi
    
    # Force Secure Boot variables if the eclass is being stubborn
    export SECUREBOOT_SIGN_CERT="/etc/refind.d/keys/refind_local.cer"
    export SECUREBOOT_SIGN_KEY="/etc/refind.d/keys/refind_local.key"
    
    einfo "Manual Override applied: EFIARCH=${EFIARCH} for ${CATEGORY}/${PN}"
}
