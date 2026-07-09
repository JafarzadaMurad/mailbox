#!/usr/bin/env bash
# =============================================================================
#  install-cert-sync.sh
#  sync-certs.sh-i systemd timer kimi qurur:
#   - reboot-dan 2 dəqiqə sonra
#   - hər gün
#  işə düşür. Beləcə Caddy sertifikatı yeniləyəndə Mailcow avtomatik alır.
#
#  İşlət:  sudo bash scripts/install-cert-sync.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "root icazəsi lazımdır:  sudo bash scripts/install-cert-sync.sh" >&2
  exit 1
fi

cat > /etc/systemd/system/mailcow-cert-sync.service <<EOF
[Unit]
Description=Caddy sertifikatını Mailcow-a sinxronla
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash ${SCRIPT_DIR}/sync-certs.sh
EOF

cat > /etc/systemd/system/mailcow-cert-sync.timer <<EOF
[Unit]
Description=Mailcow sertifikat sinxronizasiyasını mütəmadi işə sal

[Timer]
OnBootSec=2min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mailcow-cert-sync.timer
echo "Timer quruldu. Dərhal bir dəfə işlədilir..."
systemctl start mailcow-cert-sync.service || true
systemctl status mailcow-cert-sync.timer --no-pager || true
