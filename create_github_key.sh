#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "" ]]; then
  echo "Usage: $0 <email> [label]" >&2
  echo "Example: $0 you@work.com work" >&2
  exit 1
fi

email="$1"
label="${2:-}"
if [[ -z "$label" ]]; then
  # derive a stable label from the email local part
  label="${email%@*}"
  label="${label//[^a-zA-Z0-9_-]/_}"
fi

key_path="$HOME/.ssh/id_ed25519_github_${label}"
config_path="$HOME/.ssh/config"
host_alias="github-${label}"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

echo "Generating key: $key_path"
if [[ -f "$key_path" || -f "${key_path}.pub" ]]; then
  echo "Error: key already exists at $key_path" >&2
  exit 1
fi

ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""

# Ensure ssh config exists
if [[ ! -f "$config_path" ]]; then
  touch "$config_path"
  chmod 600 "$config_path"
fi

# Add host entry if missing
if ! grep -q "^Host ${host_alias}$" "$config_path"; then
  {
    echo ""
    echo "Host ${host_alias}"
    echo "  HostName github.com"
    echo "  User git"
    echo "  IdentityFile ${key_path}"
    echo "  IdentitiesOnly yes"
  } >> "$config_path"
  echo "Added SSH config entry for ${host_alias}"
else
  echo "SSH config already has Host ${host_alias}, skipping config update"
fi

echo ""
echo "Public key (add to GitHub account):"
cat "${key_path}.pub"

echo ""
echo "Use this remote format for that account:"
echo "  git@${host_alias}:OWNER/REPO.git"
