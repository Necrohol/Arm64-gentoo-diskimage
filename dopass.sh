# -----------------------------
# Setup temporary root + gentoo user with nagging password change
# -----------------------------
TEMP_PASS="Arm64Gentoo"
USERNAME="gentoo"
MAX_LOGINS=10

echo "[INFO] Setting temporary root password..."
echo "root:${TEMP_PASS}" | chpasswd

echo "[INFO] Creating default user '$USERNAME'..."
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -G wheel,video,audio,input,network -s /bin/bash "$USERNAME"
    echo "${USERNAME}:${TEMP_PASS}" | chpasswd
    echo "[INFO] User $USERNAME created with temporary password"
else
    echo "[INFO] User $USERNAME already exists"
fi

# Force password change on first login
chage -d 0 root
chage -d 0 "$USERNAME"

# Ensure wheel group can sudo
if ! grep -q "^%wheel" /etc/sudoers; then
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
    echo "[INFO] Added wheel group to sudoers"
fi

# -----------------------------
# PAM login attempts limit & nag
# -----------------------------
# Enable max 10 login attempts
for user in root "$USERNAME"; do
    sudo pam-auth-update --enable mkhomedir >/dev/null 2>&1 || true
    echo "auth required pam_tally2.so deny=${MAX_LOGINS} onerr=fail unlock_time=0 even_deny_root" \
        | sudo tee -a /etc/pam.d/common-auth >/dev/null
done

# Add login nag via MOTD
cat << 'EOF_MOTD' > /etc/motd
***********************************************
* WARNING: Temporary password in use!       *
* Please change it immediately.            *
* Max login attempts: 10                    *
***********************************************
EOF_MOTD
