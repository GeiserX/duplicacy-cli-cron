#!/usr/bin/env sh
# Wipe all Duplicacy repo metadata so config scripts can re-initialize.
# Run this BEFORE running the config scripts when changing storage layout.

# Unraid servers
cd /local_shares/Multimedia 2>/dev/null && rm -rf .duplicacy/
cd /local_shares/appdata 2>/dev/null && rm -rf .duplicacy/
cd /local_shares/system 2>/dev/null && rm -rf .duplicacy/
cd /boot_usb 2>/dev/null && rm -rf .duplicacy/

# Ubuntu servers (geiserct)
cd /local_crontab 2>/dev/null && rm -rf .duplicacy/
cd /local_etc 2>/dev/null && rm -rf .duplicacy/
cd /local_home 2>/dev/null && rm -rf .duplicacy/
cd /local_tailscale 2>/dev/null && rm -rf .duplicacy/

echo "All .duplicacy directories removed."
