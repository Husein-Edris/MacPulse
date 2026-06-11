# Local Monitor

A lightweight, zero-dependency terminal dashboard for monitoring websites and macOS system health. Runs entirely on your machine with pure Bash scripts -- no cloud services, no subscriptions, no Docker.

![macOS](https://img.shields.io/badge/macOS-compatible-brightgreen)
![Bash](https://img.shields.io/badge/Bash-5.0+-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Dashboard Preview

```
  SYSTEM MONITOR                                    2026-02-11 14:56:17
  ──────────────────────────────────────────────────────────────────────
  ● Active  checking every 10 min          last: 16s ago  next: in 9m
  CPU  ▓░░░░░░░░░░░  16.0% / 12 cores     LOAD     3.44 4.73 5.17
  RAM  ▓▓▓▓▓▓▓▓▓▓▓░  15/16.0GB (93.8%)    UPTIME   13 days
  DISK ▓▓▓▓▓▓▓▓▓▓▓░  232.8/250.7GB (92%)
  ──────────────────────────────────────────────────────────────────────
  TOP PROCESSES
  CPU   WindowServer   15%  tccd           11%  claude         9%
  RAM   Brave          4.5% Brave          3.2% Brave          3.2%
  ──────────────────────────────────────────────────────────────────────
  GITHUB  @Husein-Edris
  446 contributions this year              repos: 16  streak: 1d
  Create branch Refactor-ACF-field-reg...  headless-wp-theme
  Merge                                    headless-wp-theme
  PR merged: 002-fix-customer-employee...  Personal-Manager
  ──────────────────────────────────────────────────────────────────────
  SECURITY
  ● Firewall         ON                    ● SIP              ON
  ● FileVault        ON                    ● Gatekeeper       ON
  ──────────────────────────────────────────────────────────────────────
  WEBSITES  all 6 up
  ● edrishusein.com              200   565ms
  ● virtualinternships.com       200   2412ms
  ● bemsventures.de              200   842ms
  ● susanne-barth.com            200   592ms
  ● martina-velmeden.de          200   557ms
  ● ideel.ch                     200   530ms
  ──────────────────────────────────────────────────────────────────────
  monitor-start | monitor-stop | monitor-status | monitor
```

> The actual dashboard uses color-coded output: green for healthy, yellow for warnings, red for critical thresholds.

---

## Features

### Website Monitoring
- **HTTP status codes** for each site (200, 301, 404, 500, etc.)
- **Response time** in milliseconds with color thresholds (green < 800ms, yellow < 2000ms, red > 2000ms)
- **Downtime detection** with incident log history
- **macOS notifications** when a site goes down

### System Health
- **CPU usage** with visual progress bar (sourced from `top`, matches Activity Monitor)
- **RAM usage** with bar and exact GB values
- **Disk usage** using APFS container-level data (matches macOS Storage settings)
- **Load average** (1, 5, 15 minute)
- **Uptime** tracker

### Top Processes
- **Top 3 CPU consumers** with percentage
- **Top 3 RAM consumers** with percentage
- Color-coded: green < 30%, yellow < 60%, red > 60%

### GitHub Integration
- **Yearly contributions** total (scraped from contribution graph)
- **Current streak** in days
- **Public repos** count
- **Last 3 activities** with project name (commits, PRs, branches, merges)

### Security Audit
- **Firewall** status (ON/OFF)
- **FileVault** disk encryption status
- **SIP** (System Integrity Protection) status
- **Gatekeeper** status

### Alerts
- Native **macOS notifications** for:
  - Website downtime
  - CPU exceeding threshold (default: 90%)
  - RAM exceeding threshold (default: 90%)
  - Disk exceeding threshold (default: 85%)

---

## Project Structure

```
monitoring/
├── config.sh            # All settings in one place
├── monitor.sh           # Background daemon (data collector)
├── monitor-view.sh      # Terminal dashboard (viewer)
├── logs/
│   ├── monitoring.log   # Timestamped log of all checks
│   └── latest.json      # Most recent check results (JSON)
├── .monitor.pid         # PID file for background process
└── README.md
```

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/Husein-Edris/local-monitor.git
cd local-monitor
```

Edit `config.sh` with your websites:

```bash
WEBSITES=(
    "https://your-site.com/"
    "https://another-site.com/"
)
```

### 2. Make scripts executable

```bash
chmod +x monitor.sh monitor-view.sh
```

### 3. Run a single check

```bash
./monitor.sh once
```

### 4. Start background monitoring

```bash
./monitor.sh start
# Monitor started (PID 12345)
# Checking every 10 minutes
```

### 5. View the dashboard

```bash
./monitor-view.sh          # One-time snapshot
./monitor-view.sh live     # Auto-refresh every 30s
./monitor-view.sh log      # Tail raw log file
```

### 6. Stop monitoring

```bash
./monitor.sh stop
```

---

## Configuration

All settings live in `config.sh`:

| Setting | Default | Description |
|---|---|---|
| `WEBSITES` | _(array)_ | URLs to monitor |
| `CHECK_INTERVAL` | `600` | Seconds between checks (600 = 10 min) |
| `CURL_TIMEOUT` | `15` | Max seconds to wait for a response |
| `MONITOR_SERVER` | `yes` | Enable local machine metrics |
| `NOTIFY_ON_FAILURE` | `yes` | macOS notification alerts |
| `CPU_ALERT_THRESHOLD` | `90` | CPU % to trigger alert |
| `RAM_ALERT_THRESHOLD` | `90` | RAM % to trigger alert |
| `DISK_ALERT_THRESHOLD` | `85` | Disk % to trigger alert |
| `GITHUB_USER` | _(string)_ | GitHub username for activity tracking |

---

## Shell Aliases (Optional)

Add these to your `~/.zshrc` or `~/.bashrc` for quick access:

```bash
alias monitor='/path/to/monitoring/monitor-view.sh live'
alias monitor-view='/path/to/monitoring/monitor-view.sh'
alias monitor-start='/path/to/monitoring/monitor.sh start'
alias monitor-stop='/path/to/monitoring/monitor.sh stop'
alias monitor-status='/path/to/monitoring/monitor.sh status'
```

Then just type `monitor` from anywhere to open the live dashboard.

---

## How It Works

### Architecture

```
┌─────────────┐     ┌──────────┐     ┌────────────────┐
│  monitor.sh  │────▶│  logs/   │◀────│ monitor-view.sh │
│  (daemon)    │     │  .log    │     │  (dashboard)    │
│              │     │  .json   │     │                 │
│  curl        │     └──────────┘     │  grep + awk     │
│  top         │                      │  ANSI colors    │
│  diskutil    │                      │  progress bars  │
│  GitHub API  │                      │  cursor control │
└─────────────┘                      └────────────────┘
```

**monitor.sh** runs as a background daemon, collecting data every N seconds and writing structured log lines. **monitor-view.sh** reads the log file and renders a color-coded terminal dashboard. The two scripts communicate only through the log file -- no sockets, no databases.

### Data Collection

| Metric | Source | Why |
|---|---|---|
| CPU | `top -l 1 -s 0` | Matches Activity Monitor (user + sys) |
| RAM | `top` PhysMem line | Matches Activity Monitor used/unused |
| Disk | `diskutil apfs list` | Container-level usage matching macOS Storage |
| Websites | `curl` with timing | HTTP code + response time in ms |
| Processes | `ps -eo pcpu,comm` | Top 3 sorted by CPU and RAM |
| Security | `socketfilterfw`, `fdesetup`, `csrutil`, `spctl` | macOS security subsystems |
| GitHub | GitHub API + contributions page | No auth token needed for public data |

### Log Format

Each check writes structured, pipe-delimited lines:

```
[2026-02-11 14:35:10] SITE | UP | 200 | 538ms | https://edrishusein.com/
[2026-02-11 14:35:10] SRV  | CPU: 15.5% (12 cores) | RAM: 16/16.0GB (100.0%) | Load: 6.04 5.34 5.66 | Disk: 231.6/250.7GB(92%) | Up: 13 days
[2026-02-11 14:35:10] PROC | CPU: Brave 21%,claude 14%,tccd 11% | RAM: Brave 3.9%,Brave 2.9%,Brave 2.3%
[2026-02-11 14:35:10] SEC  | Firewall: ON | FileVault: ON | SIP: ON | Gatekeeper: ON
[2026-02-11 14:35:10] GH   | Year: 446 | Streak: 1d | Week: 2/7 | Today: 0 | Repos: 16 | Active: edrishusein.com(8) | Last3: Create branch feat-xyz@my-repo;Merge@my-repo;PR merged: fix-bug@other-repo
```

### Dashboard Rendering

The viewer uses a buffered rendering approach to prevent screen flicker:

1. All output is generated into a variable via `_render_dashboard()`
2. Screen is cleared with `\033[H\033[J` (cursor home + erase)
3. Entire buffer is printed at once

Column alignment uses ANSI cursor positioning (`\033[<col>G`) instead of `printf` width specifiers, which avoids misalignment from invisible escape code characters.

---

## Requirements

- **macOS** (uses macOS-specific commands: `top`, `diskutil`, `osascript`, `sysctl`)
- **Bash** 4.0+
- **curl** (pre-installed on macOS)
- **python3** (pre-installed on macOS, used for timing calculations and GitHub data parsing)

No additional packages, dependencies, or installations required.

---

## Performance

The monitor is designed to be lightweight:

- Background daemon uses **< 0.1% CPU** when idle (sleeping between checks)
- Each check cycle takes **~10-15 seconds** (mostly network latency from website checks + GitHub API)
- Log file grows at approximately **1 KB per check** (~144 KB/day at 10-minute intervals)
- Dashboard viewer is a one-shot read of the log file -- no persistent process

---

## Extending

### Add a new website

Edit `config.sh` and add to the `WEBSITES` array:

```bash
WEBSITES=(
    "https://your-site.com/"
    "https://new-site.com/"     # just add here
)
```

### Change check frequency

```bash
CHECK_INTERVAL=300   # every 5 minutes
CHECK_INTERVAL=60    # every minute
CHECK_INTERVAL=1800  # every 30 minutes
```

### Disable a section

```bash
MONITOR_SERVER="no"   # skip system metrics
GITHUB_USER=""        # skip GitHub integration
NOTIFY_ON_FAILURE="no"  # disable notifications
```

---

## Built With

- Pure **Bash** scripting
- macOS native tools (`top`, `diskutil`, `sysctl`, `osascript`)
- **curl** for HTTP checks
- **GitHub REST API** for activity data
- ANSI escape codes for terminal UI

---

## License

MIT License. Free to use, modify, and distribute.



  - Dashboard preview with ASCII representation of the terminal output                                                                 
  - All features broken down by section (websites, system health, processes, GitHub, security, alerts)
  - Project structure file tree                                                                                                        
  - Quick start guide (clone, configure, run)                                                                                        
  - Configuration table with all settings and defaults                                                                               
  - Shell aliases setup                                                                        
  - Architecture diagram showing how monitor.sh and monitor-view.sh communicate via log files
  - Data collection sources table explaining why each tool was chosen
  - Log format with real examples
  - Rendering technique explanation (buffered output, cursor positioning)
  - Requirements and performance notes
  - Extending section for adding sites, changing intervals, disabling sections

