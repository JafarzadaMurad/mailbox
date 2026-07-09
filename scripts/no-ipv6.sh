#!/usr/bin/env bash
# =============================================================================
#  no-ipv6.sh — verilən əmri "IPv6 çıxışı yoxdur" mühitində işlədir.
#
#  İşlət:  bash scripts/no-ipv6.sh ./generate_config.sh
#
#  NİYƏ LAZIMDIR
#  -------------
#  Mailcow-un _modules/scripts/ipv6_controller.sh faylı belə işləyir:
#
#    configure_ipv6() {
#      get_ipv6_support                      # DETECTED_IPV6 təyin edir
#      if [[ "$DETECTED_IPV6" != "true" ]]; then
#         ... ENABLE_IPV6=false; return      # <-- daemon.json-a TOXUNMUR
#      fi
#      docker_daemon_edit                    # <-- "systemctl restart docker" EDİR
#    }
#
#  Bizim serverdə Caddy + 30-a yaxın konteyner işləyir. Docker daemon-un
#  restart olunması hamısını yıxardı. `n` cavabı isə skripti `exit 1` ilə
#  dayandırır. ENABLE_IPV6=false env dəyişəni də kömək etmir — upstream kodda
#  MANUAL_SETTING hesablanır, lakin heç vaxt istifadə olunmur (bug).
#
#  get_ipv6_support() xarici IPv6 çıxışını `ping6` / `ping -6` ilə yoxlayır.
#  Ona görə yalnız BU prosesin PATH-ına həmişə uğursuz olan saxta `ping`/`ping6`
#  qoyuruq. Nəticədə DETECTED_IPV6=false olur, daemon.json toxunulmur və
#  mailcow özü mailcow.conf-a ENABLE_IPV6=false yazır.
#
#  Host-un şəbəkəsinə, sysctl-ə və ya Docker konfiqinə HEÇ BİR dəyişiklik
#  edilmir. Shim yalnız bu prosesin ömrü boyu mövcuddur.
#
#  Eyni səbəbdən Mailcow-u yeniləyəndə də bu wrapper-dən istifadə et:
#      bash scripts/mailcow-update.sh
# =============================================================================
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "İstifadə: bash scripts/no-ipv6.sh <əmr> [arqumentlər...]" >&2
  exit 2
fi

SHIM_DIR="$(mktemp -d)"
cleanup() { rm -rf "$SHIM_DIR"; }
trap cleanup EXIT

for bin in ping ping6; do
  printf '#!/bin/sh\nexit 1\n' > "$SHIM_DIR/$bin"
  chmod +x "$SHIM_DIR/$bin"
done

set +e
PATH="$SHIM_DIR:$PATH" "$@"
rc=$?
set -e
exit "$rc"
