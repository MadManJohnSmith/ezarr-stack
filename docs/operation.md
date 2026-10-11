# Day-to-Day Operations & Maintenance

> [**English**](operation.md) · [**Español**](operation.es.md)

Comprehensive guide for operating, supervising, and troubleshooting the \*arr media stack using `ezarrctl`.

---

## 1. Unified Control Interface: `ezarrctl`

The entire server is managed through a single binary:

```bash
ezarrctl
```

### Command Subcommands Matrix

| Subcommand | Purpose | Mutates System? |
|---|---|:---:|
| `status` | Reports running/stopped status of all managed services | No |
| `start [service...]` | Starts one, multiple, or all configured services | Yes |
| `stop [service...]` | Gracefully stops services with timeout fallback | Yes |
| `restart [service...]` | Sequential stop and start adhering to dependency graph | Yes |
| `logs [-f] [service]` | Streams logs with timestamp and service prefixes | No |
| `backup` | Creates snapshot of config, state, and databases with SHA-256 | Writes to backup dir |
| `update` | Runs backup → updates components → executes doctor checks | Yes |
| `doctor` | Runs independent diagnostic probes on ports, mounts, and state | No |
| `secrets` | CLI management for API keys, tokens, and credentials | Yes |
| `exit-codes` | Prints standardized CLI exit code table | No |
| `version` | Displays stack version, platform, and architecture | No |

### Smart Environment Detection

`ezarrctl` never blindly assumes systemd (`ezarrctl`, function `svc_manager`):
- **Phone TWRP Chroot**: Invokes `arr-stack` (direct process spawning, PID tracking, and `pgrep`).
- **Standard Linux Hosts**: Interacts with `systemctl`.

---

## 2. Essential Daily Commands

```bash
# 1. Quick status inspection
ezarrctl status

# 2. Start all services
ezarrctl start

# 3. Stream live logs
ezarrctl logs -f

# 4. Generate system backup
ezarrctl backup

# 5. Run health diagnostics
ezarrctl doctor
```

---

## 3. Safe Secrets Administration

Manage credentials without editing raw config files:

```bash
# List configured secret keys and presence
ezarrctl secrets list

# Update a specific secret value
ezarrctl secrets set EZARR_CAMERA_RTSP_PASS "new-password"

# Audit permissions and check for placeholder values
ezarrctl secrets doctor
```

All values are written to `/etc/ezarr/secrets.conf` with strict `0600` permissions.

---

## 4. Diagnostics & Troubleshooting

When `ezarrctl doctor` detects an anomaly:

```bash
# Run full diagnostic suite
ezarrctl doctor
```

Example output:
```text
[OK]   Storage mount /data/media (mergerfs) active
[OK]   Google Drive VFS mount /data/remote active
[OK]   Process qbittorrent-nox listening on :8080 and :6881
[OK]   Jellyfin server responding on :8096
[OK]   All secret keys set with valid 0600 permissions
```

If a service fails to start, inspect its dedicated log:

```bash
ezarrctl logs jellyfin
```
