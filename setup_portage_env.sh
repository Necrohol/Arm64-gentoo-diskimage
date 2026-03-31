#!/bin/bash
# Prepping the local environment for the Docker mount
ENV_DIR="./portage/env"
PKG_DIR="./portage/package.env"
mkdir -p "$ENV_DIR"

echo "Configuring EFI architecture hooks..."

cat << 'EOF' > "${ENV_DIR}/efi-logic"
pre_pkg_setup() {
    if [[ ${ARCH} == "arm64" ]]; then
        export EFIARCH=aa64
        export BUILDARCH=aarch64
    elif [[ ${ARCH} == "riscv" ]]; then
        export EFIARCH=riscv64
        export BUILDARCH=riscv64
    fi
    einfo "Build targeting EFIARCH: ${EFIARCH}"
}
EOF

echo "sys-boot/refind efi-logic" > "$PKG_DIR"
echo "sys-boot/shim efi-logic" >> "$PKG_DIR"
echo "sys-boot/uefi-mkconfig efi-logic" >> "$PKG_DIR"
