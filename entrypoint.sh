#!/bin/sh
# Railway entrypoint for Verdaccio.
#
# Runs as root: prepares the volume, renders the registry config, seeds the
# operator account, then hands over to the image's own entrypoint as uid 10001.
set -eu

UID_N=10001
GID_N=0
DATA_DIR="${VERDACCIO_DATA_DIR:-/data}"
STORAGE_DIR="$DATA_DIR/storage"
HTPASSWD_FILE="$DATA_DIR/htpasswd"
STAMP_FILE="$DATA_DIR/.admin-stamp"
CONF_FILE=/verdaccio/conf/config.yaml

log() { echo "railway-entrypoint: $*"; }

# Every Railway volume ships a lost+found, so the registry's own data directory
# has to sit one level below the mount root rather than at it.
mkdir -p "$STORAGE_DIR"
chown "$UID_N:$GID_N" "$DATA_DIR" "$STORAGE_DIR"
if [ ! -f "$DATA_DIR/.railway-owned" ]; then
  log "first boot on this volume — taking ownership of $DATA_DIR"
  chown -R "$UID_N:$GID_N" "$DATA_DIR"
  : > "$DATA_DIR/.railway-owned"
  chown "$UID_N:$GID_N" "$DATA_DIR/.railway-owned"
fi

# --- config -----------------------------------------------------------------
# Only the handful of genuine choices are substituted; the rest of the config is
# reviewed here rather than pasted into a service variable.
PACKAGE_ACCESS="${VERDACCIO_PACKAGE_ACCESS:-\$authenticated}"
MAX_USERS="${VERDACCIO_MAX_USERS:--1}"
UPLINK_URL="${VERDACCIO_UPLINK_URL:-https://registry.npmjs.org/}"
PRIVATE_SCOPE="${VERDACCIO_PRIVATE_SCOPE:-}"

# A scope named here is served locally only — never merged with whatever the
# upstream registry happens to publish under the same name.
SCOPE_BLOCK=/tmp/private-scope.yaml
: > "$SCOPE_BLOCK"
if [ -n "$PRIVATE_SCOPE" ]; then
  case "$PRIVATE_SCOPE" in @*) ;; *) PRIVATE_SCOPE="@$PRIVATE_SCOPE" ;; esac
  {
    printf "  '%s/*':\n" "$PRIVATE_SCOPE"
    printf '    access: $authenticated\n'
    printf '    publish: $authenticated\n'
    printf '    unpublish: $authenticated\n'
    printf '\n'
  } > "$SCOPE_BLOCK"
  log "private scope $PRIVATE_SCOPE/* will not be proxied upstream"
fi

STAGED=/tmp/config.staged.yaml
awk -v blockfile="$SCOPE_BLOCK" '
  /__PRIVATE_SCOPE_BLOCK__/ {
    while ((getline line < blockfile) > 0) print line
    close(blockfile)
    next
  }
  { print }
' /verdaccio/conf/config.template.yaml > "$STAGED"

sed -e "s|__STORAGE__|$STORAGE_DIR|g" \
    -e "s|__HTPASSWD__|$HTPASSWD_FILE|g" \
    -e "s|__MAX_USERS__|$MAX_USERS|g" \
    -e "s|__UPLINK_URL__|$UPLINK_URL|g" \
    -e "s|__PACKAGE_ACCESS__|$PACKAGE_ACCESS|g" \
    "$STAGED" > "$CONF_FILE"
chown "$UID_N:$GID_N" "$CONF_FILE"
chmod 0644 "$CONF_FILE"
if grep -q '__[A-Z_]*__' "$CONF_FILE"; then
  log "FATAL: unsubstituted placeholder left in $CONF_FILE"
  grep -n '__[A-Z_]*__' "$CONF_FILE"
  exit 1
fi
log "rendered config: storage=$STORAGE_DIR access=$PACKAGE_ACCESS max_users=$MAX_USERS uplink=$UPLINK_URL"

# --- operator account -------------------------------------------------------
# max_users defaults to -1, so nobody can `npm adduser` against this registry.
# The account is therefore seeded here, and only when the configured pair has
# actually changed — otherwise a password the operator rotated through
# `npm profile` would be reverted on every deploy.
ADMIN_USER="${VERDACCIO_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${VERDACCIO_ADMIN_PASSWORD:-}"

if [ -n "$ADMIN_PASSWORD" ]; then
  stamp=$(printf '%s' "$ADMIN_USER:$ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)
  prev=$(cat "$STAMP_FILE" 2>/dev/null || echo none)
  if [ ! -f "$HTPASSWD_FILE" ] || [ "$prev" != "$stamp" ]; then
    [ -f "$HTPASSWD_FILE" ] || : > "$HTPASSWD_FILE"
    printf '%s\n' "$ADMIN_PASSWORD" | htpasswd -i -B -C 10 "$HTPASSWD_FILE" "$ADMIN_USER"
    printf '%s' "$stamp" > "$STAMP_FILE"
    log "seeded registry account '$ADMIN_USER'"
  else
    log "registry account '$ADMIN_USER' already current — left untouched"
  fi
  chown "$UID_N:$GID_N" "$HTPASSWD_FILE" "$STAMP_FILE"
  chmod 0640 "$HTPASSWD_FILE"
else
  log "VERDACCIO_ADMIN_PASSWORD is empty — no account seeded, nobody can log in"
  if [ ! -f "$HTPASSWD_FILE" ]; then
    : > "$HTPASSWD_FILE"
    chown "$UID_N:$GID_N" "$HTPASSWD_FILE"
    chmod 0640 "$HTPASSWD_FILE"
  fi
fi

# The registry has no use for the plaintext password; keep it out of the app's
# environment and out of anything that dumps it.
unset VERDACCIO_ADMIN_PASSWORD

exec su-exec "$UID_N:$GID_N" "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint.real" "$@"
