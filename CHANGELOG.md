# Changelog

## [0.2.0] — 2026-09-04

Red team hardening and new commands.

- **Security:** bind to `127.0.0.1` by default instead of `0.0.0.0` (configurable via `SEARXNG_BIND`)
- **Security:** replace alpine sidecar with `podman cp` for settings seeding (removes unpinned alpine dependency)
- **Security:** stop suppressing `podman machine start` stderr so failures are diagnosable
- Add `update` command: pulls latest image, recreates container if newer, preserves settings
- Add `logs` command: show container logs (pass podman logs flags through)
- Add `reset` command: interactive destructive removal of container and volume
- Add port validation: `SEARXNG_PORT` must be numeric 1-65535
- Replace `exit 0` with `return 0` inside functions (safe to source)
- Add `warn()` helper

## [0.1.0] — 2026-09-04

Initial release.

- Podman-based SearXNG setup with persistent volume
- Cross-platform support: macOS and GNU/Linux
- Auto-generated secret key on first run
- Setup script with start, stop, teardown, and status commands
- Template `settings.yml` with sensible defaults
- Documentation for auto-start via launchd (macOS) and systemd (Linux)
