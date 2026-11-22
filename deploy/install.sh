#!/usr/bin/env bash
# One-time setup on the gaming box (also re-run by deadbeat-sync when deploy/ changes):
#   git clone github-deadbeat:manuelnagele/deadbeat ~/deadbeat && ~/deadbeat/deploy/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNITS="$HOME/.config/systemd/user"
mkdir -p "$UNITS"
sed "s|@REPO@|$REPO|g" "$REPO/deploy/deadbeat-sync.service" > "$UNITS/deadbeat-sync.service"
systemctl --user daemon-reload

[ "${1:-}" = "--units-only" ] && exit 0

systemctl --user enable --now deadbeat-sync.service
systemctl --user --no-pager status deadbeat-sync.service | grep -E '●|Active'
