# searxng-local

Run [SearXNG](https://searxng.org) locally in a Podman container with persistent configuration. One script, no Docker, no compose files.

SearXNG is a privacy-respecting metasearch engine that aggregates results from 70+ search engines without tracking you.

## Prerequisites

- [Podman](https://podman.io/docs/installation) installed and running

### macOS

```bash
brew install podman
podman machine init
podman machine start
```

### GNU/Linux (Debian/Ubuntu)

```bash
sudo apt install podman
```

### GNU/Linux (Fedora/RHEL)

```bash
sudo dnf install podman
```

## Quick start

```bash
git clone https://github.com/t0lkim/searxng-local.git
cd searxng-local
chmod +x setup.sh
./setup.sh
```

SearXNG is now running at [http://localhost:8080](http://localhost:8080).

## Usage

```bash
./setup.sh              # Create and start (or start if already created)
./setup.sh stop          # Stop the container
./setup.sh status        # Show container status
./setup.sh teardown      # Remove container (preserves settings volume)
./setup.sh help          # Show all commands
```

### Custom port

```bash
SEARXNG_PORT=9090 ./setup.sh
```

## What it does

The setup script:

1. Checks that Podman is installed and running (starts the Podman VM on macOS if needed)
2. Creates a named volume (`searxng-data`) for persistent configuration
3. Generates a unique `secret_key` and writes `settings.yml` into the volume
4. Pulls the official SearXNG image and starts the container

On subsequent runs it starts the existing container — no duplicate containers, no lost settings.

## Configuration

Settings persist in the `searxng-data` Podman volume. To edit:

```bash
# View current settings
podman exec searxng cat /etc/searxng/settings.yml

# Edit in-place
podman exec -it searxng vi /etc/searxng/settings.yml

# Or copy out, edit, copy back
podman cp searxng:/etc/searxng/settings.yml ./my-settings.yml
# ... edit my-settings.yml ...
podman cp ./my-settings.yml searxng:/etc/searxng/settings.yml
podman restart searxng
```

The bundled `settings.yml` uses SearXNG defaults with `image_proxy` enabled. See the [SearXNG settings documentation](https://docs.searxng.org/admin/settings/) for all options.

## Auto-start (optional)

The container is created with `--restart always`, so it starts automatically when the Podman runtime is running. To start Podman itself at login/boot:

### macOS (launchd)

Create `~/Library/LaunchAgents/local.searxng.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.searxng</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/path/to/searxng-local/setup.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/searxng.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/searxng.log</string>
</dict>
</plist>
```

Then load it:

```bash
launchctl load ~/Library/LaunchAgents/local.searxng.plist
```

The script waits for the Podman machine before starting the container.

### GNU/Linux (systemd user unit)

Create `~/.config/systemd/user/searxng.service`:

```ini
[Unit]
Description=SearXNG local search
After=default.target

[Service]
Type=oneshot
ExecStart=/path/to/searxng-local/setup.sh
RemainAfterExit=yes
ExecStop=/path/to/searxng-local/setup.sh stop

[Install]
WantedBy=default.target
```

Then enable it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now searxng.service
```

## Uninstall

```bash
./setup.sh teardown                  # Remove container
podman volume rm searxng-data        # Remove settings
podman rmi docker.io/searxng/searxng # Remove image
```

## Licence

[MIT](LICENSE)
