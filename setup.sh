#!/usr/bin/env bash
set -euo pipefail

# searxng-local setup
# Creates a local SearXNG instance using Podman with persistent configuration.

CONTAINER_NAME="searxng"
VOLUME_NAME="searxng-data"
IMAGE="docker.io/searxng/searxng:latest"
PORT="${SEARXNG_PORT:-8080}"
BIND="${SEARXNG_BIND:-127.0.0.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="http://localhost:${PORT}/"

info() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2
}

error() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

validate_port() {
  [[ "$PORT" =~ ^[0-9]+$ ]] || error "SEARXNG_PORT must be a number, got: '${PORT}'"
  if (( PORT < 1 || PORT > 65535 )); then
    error "SEARXNG_PORT must be between 1 and 65535, got: ${PORT}"
  fi
}

check_podman() {
  command -v podman >/dev/null 2>&1 || error "podman not found. Install it first:
  macOS:   brew install podman && podman machine init && podman machine start
  Linux:   https://podman.io/docs/installation"
}

check_podman_running() {
  if [[ "$(uname)" == "Darwin" ]]; then
    if ! podman machine info --format '{{.Host.MachineState}}' 2>/dev/null | grep -qi running; then
      info "Starting Podman machine..."
      podman machine start || error "Failed to start Podman machine. Run: podman machine init && podman machine start"
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
  validate_port
  check_podman
  check_podman_running

  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    local state
    state="$(podman inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")"
    if [[ "$state" == "running" ]]; then
      info "SearXNG is already running at ${BASE_URL}"
      return 0
    fi
    info "Starting existing container..."
    podman start "$CONTAINER_NAME"
    info "SearXNG running at ${BASE_URL}"
    return 0
  fi

  info "Creating volume ${VOLUME_NAME}..."
  podman volume create "$VOLUME_NAME" 2>/dev/null || true

  local tmpdir
  tmpdir="$(mktemp -d)"
  create_settings "${tmpdir}/settings.yml"

  info "Pulling ${IMAGE}..."
  podman pull "$IMAGE"

  # Seed settings into the volume via a temporary container.
  # Works on both macOS (volume inside VM) and Linux.
  local seed_cid
  seed_cid="$(podman create --name searxng-seed -v "${VOLUME_NAME}:/etc/searxng" "$IMAGE" true)"
  podman cp "${tmpdir}/settings.yml" "${seed_cid}:/etc/searxng/settings.yml"
  podman rm "$seed_cid" >/dev/null
  rm -rf "$tmpdir"

  info "Starting SearXNG..."
  podman run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${BIND}:${PORT}:8080" \
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

update() {
  if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    error "No SearXNG container found. Run './setup.sh' first."
  fi

  info "Pulling latest ${IMAGE}..."
  local old_id
  old_id="$(podman inspect --format '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null)"
  podman pull "$IMAGE"
  local new_id
  new_id="$(podman inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null)"

  if [[ "$old_id" == "$new_id" ]]; then
    info "Already running the latest image."
    return 0
  fi

  info "New image available. Recreating container..."
  podman stop "$CONTAINER_NAME" 2>/dev/null || true
  podman rm "$CONTAINER_NAME"

  podman run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${BIND}:${PORT}:8080" \
    -v "${VOLUME_NAME}:/etc/searxng" \
    -e "SEARXNG_BASE_URL=${BASE_URL}" \
    "$IMAGE"

  info "SearXNG updated and running at ${BASE_URL}"
}

logs() {
  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    podman logs "${@:---tail=50}" "$CONTAINER_NAME"
  else
    error "No SearXNG container found."
  fi
}

reset() {
  warn "This will destroy the container AND all settings."
  printf "Continue? [y/N] "
  read -r confirm
  if [[ "$confirm" != [yY] ]]; then
    info "Aborted."
    return 0
  fi

  stop 2>/dev/null || true
  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    podman rm "$CONTAINER_NAME"
  fi
  if podman volume exists "$VOLUME_NAME" 2>/dev/null; then
    podman volume rm "$VOLUME_NAME"
  fi
  info "Removed container and volume. Run './setup.sh' to start fresh."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  setup     Create and start SearXNG (default)
  start     Start an existing container
  stop      Stop the container
  update    Pull latest image and recreate container (preserves settings)
  logs      Show container logs (pass podman logs flags after)
  status    Show container status
  teardown  Remove the container (preserves settings volume)
  reset     Remove container AND settings volume (destructive)
  help      Show this message

Environment:
  SEARXNG_PORT  Port to bind (default: 8080)
  SEARXNG_BIND  Address to bind (default: 127.0.0.1)
EOF
}

case "${1:-setup}" in
  setup)    setup ;;
  start)    setup ;;
  stop)     stop ;;
  update)   update ;;
  logs)     shift; logs "$@" ;;
  teardown) teardown ;;
  reset)    reset ;;
  status)   status ;;
  help|-h|--help) usage ;;
  *) error "Unknown command: $1. Run '$(basename "$0") help' for usage." ;;
esac
