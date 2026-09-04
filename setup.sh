#!/usr/bin/env bash
set -euo pipefail

# searxng-local setup
# Creates a local SearXNG instance using Podman with persistent configuration.

CONTAINER_NAME="searxng"
VOLUME_NAME="searxng-data"
IMAGE="docker.io/searxng/searxng:latest"
PORT="${SEARXNG_PORT:-8080}"
BASE_URL="http://localhost:${PORT}/"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

check_podman() {
  command -v podman >/dev/null 2>&1 || error "podman not found. Install it first:
  macOS:   brew install podman && podman machine init && podman machine start
  Linux:   https://podman.io/docs/installation"
}

check_podman_running() {
  if [[ "$(uname)" == "Darwin" ]]; then
    if ! podman machine info --format '{{.Host.MachineState}}' 2>/dev/null | grep -qi running; then
      info "Starting Podman machine..."
      podman machine start 2>/dev/null || error "Failed to start Podman machine. Run: podman machine init && podman machine start"
    fi
  fi
}

generate_secret_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

create_settings() {
  local settings_file="$1"
  local secret_key
  secret_key="$(generate_secret_key)"

  if [[ -f "$settings_file" ]]; then
    info "Using existing settings: $settings_file"
    return
  fi

  if [[ -f "${SCRIPT_DIR}/settings.yml" ]]; then
    cp "${SCRIPT_DIR}/settings.yml" "$settings_file"
    sed -i.bak "s/secret_key: \".*\"/secret_key: \"${secret_key}\"/" "$settings_file"
    rm -f "${settings_file}.bak"
  else
    cat > "$settings_file" <<EOF
use_default_settings: true

server:
  secret_key: "${secret_key}"
  image_proxy: true
EOF
  fi

  info "Generated settings with unique secret key"
}

setup() {
  check_podman
  check_podman_running

  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    local state
    state="$(podman inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")"
    if [[ "$state" == "running" ]]; then
      info "SearXNG is already running at ${BASE_URL}"
      exit 0
    fi
    info "Starting existing container..."
    podman start "$CONTAINER_NAME"
    info "SearXNG running at ${BASE_URL}"
    exit 0
  fi

  info "Creating volume ${VOLUME_NAME}..."
  podman volume create "$VOLUME_NAME" 2>/dev/null || true

  local mount_path
  mount_path="$(podman volume inspect "$VOLUME_NAME" --format '{{.Mountpoint}}')"

  local settings_target="${mount_path}/settings.yml"

  if [[ "$(uname)" == "Darwin" ]]; then
    # On macOS, the volume lives inside the Podman VM.
    # Copy settings via a temporary container.
    local tmpdir
    tmpdir="$(mktemp -d)"
    create_settings "${tmpdir}/settings.yml"
    podman run --rm -v "$VOLUME_NAME:/data" -v "${tmpdir}:/src:ro" alpine sh -c \
      '[ -f /data/settings.yml ] || cp /src/settings.yml /data/settings.yml'
    rm -rf "$tmpdir"
  else
    create_settings "$settings_target"
  fi

  info "Pulling ${IMAGE}..."
  podman pull "$IMAGE"

  info "Starting SearXNG..."
  podman run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${PORT}:8080" \
    -v "${VOLUME_NAME}:/etc/searxng" \
    -e "SEARXNG_BASE_URL=${BASE_URL}" \
    "$IMAGE"

  info "SearXNG running at ${BASE_URL}"
}

stop() {
  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    info "Stopping SearXNG..."
    podman stop "$CONTAINER_NAME"
    info "Stopped."
  else
    info "No SearXNG container found."
  fi
}

teardown() {
  stop 2>/dev/null || true
  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    info "Removing container..."
    podman rm "$CONTAINER_NAME"
  fi
  info "Volume ${VOLUME_NAME} preserved (contains your settings)."
  info "To remove everything: podman volume rm ${VOLUME_NAME}"
}

status() {
  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    podman inspect --format 'Name:    {{.Name}}
Image:   {{.ImageName}}
Status:  {{.State.Status}}
Started: {{.State.StartedAt}}
Port:    {{range .HostConfig.PortBindings}}{{range .}}{{.HostPort}}{{end}}{{end}}' "$CONTAINER_NAME"
  else
    info "No SearXNG container found."
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  setup     Create and start SearXNG (default)
  start     Start an existing container
  stop      Stop the container
  teardown  Remove the container (preserves volume)
  status    Show container status
  help      Show this message

Environment:
  SEARXNG_PORT  Port to bind (default: 8080)
EOF
}

case "${1:-setup}" in
  setup)    setup ;;
  start)    setup ;;
  stop)     stop ;;
  teardown) teardown ;;
  status)   status ;;
  help|-h|--help) usage ;;
  *) error "Unknown command: $1. Run '$(basename "$0") help' for usage." ;;
esac
