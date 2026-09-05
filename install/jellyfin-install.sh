#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://jellyfin.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_custom "ℹ️" "${GN}" "If NVIDIA GPU passthrough is detected, you'll be asked whether to install drivers in the container"

msg_info "Installing Dependencies"
ensure_dependencies libjemalloc2
if [[ ! -f /usr/lib/libjemalloc.so ]]; then
  ln -sf "/usr/lib/$(arch_resolve "x86_64-linux-gnu" "aarch64-linux-gnu")/libjemalloc.so.2" /usr/lib/libjemalloc.so
fi
msg_ok "Installed Dependencies"

JELLYFIN_COMPONENTS="main"
[[ "${var_jellyfin_channel:-stable}" == "unstable" ]] && JELLYFIN_COMPONENTS="main unstable"

msg_info "Setting up Jellyfin Repository"
JELLYFIN_REPO_URL="https://repo.jellyfin.org/$(get_os_info id)"
JELLYFIN_SUITE="$(get_fallback_suite "$(get_os_info id)" "$(get_os_info codename)" "$JELLYFIN_REPO_URL")"
setup_deb822_repo \
  "jellyfin" \
  "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
  "$JELLYFIN_REPO_URL" \
  "$JELLYFIN_SUITE" \
  "$JELLYFIN_COMPONENTS"
msg_ok "Set up Jellyfin Repository"

if [[ "${var_jellyfin_channel:-stable}" == "unstable" ]]; then
  # Jellyfin's unstable versions are build timestamps (e.g. 2026090423+ubu2404),
  # not a predictable semver range, so the only reliable signal is which apt
  # component actually served the resolved candidate — not what its version
  # string looks like.
  JELLYFIN_CANDIDATE="$(apt-cache policy jellyfin-server | awk '/^ *Candidate:/{print $2; exit}')"
  JELLYFIN_CANDIDATE_SOURCE="$(apt-cache madison jellyfin-server | awk -F'|' -v v="$JELLYFIN_CANDIDATE" '{gsub(/^[ \t]+|[ \t]+$/,"",$2); if ($2==v) {print $3; exit}}')"
  if [[ "$JELLYFIN_CANDIDATE_SOURCE" != *"/unstable "* ]]; then
    msg_error "Jellyfin unstable component's candidate (${JELLYFIN_CANDIDATE:-unknown}) is not being served from the unstable component. Jellyfin pauses its weekly unstable builds for a week or two around each release, and during that window unstable silently falls back to stable. Aborting instead of installing stable without asking — retry later, or install with var_jellyfin_channel=stable."
    exit 1
  fi
fi

msg_info "Installing Jellyfin"
ensure_dependencies jellyfin jellyfin-ffmpeg7
ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg
ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe
if [[ "${var_jellyfin_channel:-stable}" == "unstable" ]]; then
  $STD apt-mark hold jellyfin jellyfin-server jellyfin-web
fi
msg_ok "Installed Jellyfin"

setup_hwaccel "jellyfin"

msg_info "Configuring Jellyfin"
# Configure log rotation to prevent disk fill (keeps fail2ban compatibility) (PR: #1690 / Issue: #11224)
cat <<EOF >/etc/logrotate.d/jellyfin
/var/log/jellyfin/*.log {
    daily
    rotate 3
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
chown -R jellyfin:adm /etc/jellyfin
sleep 10
systemctl restart jellyfin
msg_ok "Configured Jellyfin"

motd_ssh
customize
cleanup_lxc
