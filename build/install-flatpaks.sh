#!/usr/bin/env bash
# build/install-flatpaks.sh — install system flatpaks listed in
# build/flatpak-list.txt. Idempotent; primary install path (flatpaks are NOT
# baked into the image — /var is only seeded on first install and never
# updated by bootc upgrades).
set -euo pipefail

LIST="$(cd "$(dirname "$0")" && grep -v '^#' flatpak-list.txt | grep -v '^$')"

# Ensure flathub remote exists.
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

for app in ${LIST}; do
    if flatpak list --system | grep -q "^${app}\b"; then
        echo "skip: ${app}"
        continue
    fi
    echo "install: ${app}"
    flatpak install --system --noninteractive flathub "${app}"
done

echo "==> flatpak install complete"
