#!/bin/bash
# Setup local CWD for Portage artifacts
mkdir -p ./portage/env ./portage/package.env ./packages

echo "Creating architecture logic..."
cat << 'EOF' > "./portage/env/efi-logic"
pre_pkg_setup() {
    if [[ ${ARCH} == "arm64" ]]; then
        export EFIARCH=aa64
    elif [[ ${ARCH} == "riscv" ]]; then
        export EFIARCH=riscv64
    fi
}
EOF

echo "sys-boot/refind efi-logic" > "./portage/package.env/efi-overrides"
echo "sys-boot/shim efi-logic" >> "./portage/package.env/efi-overrides"

echo "Ready. Run 'docker compose up' to build and drop binpkgs to ./packages"
