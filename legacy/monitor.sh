#!/bin/bash
# ============================================================
#  LOCAL MONITOR — Background website & server checker
#  Usage: ./monitor.sh start | stop | status | once
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

PID_FILE="$SCRIPT_DIR/.monitor.pid"

mkdir -p "$LOG_DIR"

# --- Helpers ------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

notify() {
    if [[ "$NOTIFY_ON_FAILURE" == "yes" ]]; then
        osascript -e "display notification \"$1\" with title \"Monitor Alert\"" 2>/dev/null
    fi
}

# --- Website Check ------------------------------------------

check_website() {
    local url="$1"
    local start_time=$(python3 -c "import time; print(time.time())")

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null)
    local curl_exit=$?

    local end_time=$(python3 -c "import time; print(time.time())")
    local response_time=$(python3 -c "print(round(($end_time - $start_time) * 1000))")

    local status="UP"
    if [[ $curl_exit -ne 0 ]] || [[ "$http_code" -ge 400 ]] 2>/dev/null; then
        status="DOWN"
        notify "$url is DOWN (HTTP $http_code)"
    fi

    log "SITE | $status | $http_code | ${response_time}ms | $url"
    echo "{\"type\":\"site\",\"url\":\"$url\",\"status\":\"$status\",\"http_code\":\"$http_code\",\"response_ms\":$response_time,\"time\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
}

# --- Server Check -------------------------------------------

check_server() {
    if [[ "$MONITOR_SERVER" != "yes" ]]; then
        return
    fi

    # Uptime
    local uptime_str
    uptime_str=$(uptime | sed 's/.*up //' | sed 's/,.*//')

    # CPU usage — from top (matches Activity Monitor)
    local cpu_usage
    local top_cpu=$(top -l 1 -s 0 2>/dev/null | grep "CPU usage")
    local cpu_user=$(echo "$top_cpu" | grep -o '[0-9.]*% user' | grep -o '[0-9.]*')
    local cpu_sys=$(echo "$top_cpu" | grep -o '[0-9.]*% sys' | grep -o '[0-9.]*')
    cpu_usage=$(python3 -c "print(round(${cpu_user:-0} + ${cpu_sys:-0}, 1))")

    # RAM — from top (matches Activity Monitor)
    local total_ram used_ram ram_pct
    local phys_mem=$(top -l 1 -s 0 2>/dev/null | grep PhysMem)
    local used_raw=$(echo "$phys_mem" | grep -o '[0-9]*G used' | grep -o '[0-9]*')
    local unused_raw=$(echo "$phys_mem" | grep -o '[0-9]*M unused' | grep -o '[0-9]*')
    # Handle case where unused is in G
    if [[ -z "$unused_raw" ]]; then
        unused_raw=$(echo "$phys_mem" | grep -o '[0-9]*G unused' | grep -o '[0-9]*')
        unused_raw=$(( ${unused_raw:-0} * 1024 ))
    fi
    total_ram=$(sysctl -n hw.memsize)
    local total_ram_gb=$(python3 -c "print(round($total_ram / 1073741824, 1))")
    local used_ram_gb=${used_raw:-0}
    ram_pct=$(python3 -c "print(round($used_ram_gb / $total_ram_gb * 100, 1))")

    # Disk — APFS container (matches macOS Storage)
    local disk_info=""
    local apfs_line=$(diskutil apfs list 2>/dev/null | grep "Capacity In Use By Volumes" | head -1)
    if [[ -n "$apfs_line" ]]; then
        local disk_used_gb=$(echo "$apfs_line" | grep -o '([0-9.]* GB)' | head -1 | grep -o '[0-9.]*')
        local disk_total_line=$(diskutil apfs list 2>/dev/null | grep "Size (Capacity Ceiling)" | head -1)
        local disk_total_gb=$(echo "$disk_total_line" | grep -o '([0-9.]* GB)' | head -1 | grep -o '[0-9.]*')
        local disk_pct=$(echo "$apfs_line" | grep -o '[0-9.]*% used' | head -1 | grep -o '[0-9.]*')
        local disk_pct_int=${disk_pct%.*}
        disk_info="${disk_used_gb:-0}/${disk_total_gb:-0}GB(${disk_pct_int:-0}%)"

        if [[ "${disk_pct_int:-0}" -ge "$DISK_ALERT_THRESHOLD" ]] 2>/dev/null; then
            notify "Disk at ${disk_pct_int}%!"
        fi
    else
        # Fallback to df
        local disk_line=$(df -h / 2>/dev/null | tail -1)
        local disk_used=$(echo "$disk_line" | awk '{print $3}')
        local disk_total=$(echo "$disk_line" | awk '{print $2}')
        local disk_pct_int=$(echo "$disk_line" | awk '{print $5}' | tr -d '%')
        disk_info="${disk_used}/${disk_total}(${disk_pct_int}%)"
    fi

    # Load average
    local load_avg
    load_avg=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')

    # CPU count
    local cpu_count
    cpu_count=$(sysctl -n hw.ncpu)

    # Alert checks
    local cpu_int=${cpu_usage%.*}
    cpu_int=${cpu_int:-0}
    if [[ "$cpu_int" -ge "$CPU_ALERT_THRESHOLD" ]] 2>/dev/null; then
        notify "CPU at ${cpu_usage}%!"
    fi

    local ram_int=${ram_pct%.*}
    if [[ "$ram_int" -ge "$RAM_ALERT_THRESHOLD" ]] 2>/dev/null; then
        notify "RAM at ${ram_pct}%!"
    fi

    log "SRV  | CPU: ${cpu_usage}% (${cpu_count} cores) | RAM: ${used_ram_gb}/${total_ram_gb}GB (${ram_pct}%) | Load: ${load_avg} | Disk: ${disk_info} | Up: ${uptime_str}"

    # Top processes by CPU
    local top_cpu=$(ps -eo pcpu,comm -r 2>/dev/null | awk 'NR>1 && NR<=4 {
        n=$2; gsub(/.*\//,"",n); gsub(/\.app.*/,"",n);
        printf "%s %.0f%%,", n, $1
    }')
    top_cpu=${top_cpu%,}

    # Top processes by RAM
    local top_ram=$(ps -eo pmem,comm -m 2>/dev/null | awk 'NR>1 && NR<=4 {
        n=$2; gsub(/.*\//,"",n); gsub(/\.app.*/,"",n);
        printf "%s %.1f%%,", n, $1
    }')
    top_ram=${top_ram%,}

    log "PROC | CPU: ${top_cpu} | RAM: ${top_ram}"

    # Open ports
    local ports=$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk 'NR>1 {
        split($9,a,":"); printf "%s:%s,", $1, a[length(a)]
    }' | tr -s ',' ',' | sed 's/,$//')
    # Deduplicate
    ports=$(echo "$ports" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    log "PORT | ${ports}"

    # Security checks
    local fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -c "enabled")
    local fv=$(fdesetup status 2>/dev/null | grep -c "On")
    local sip=$(csrutil status 2>/dev/null | grep -c "enabled")
    local gk=$(spctl --status 2>/dev/null | grep -c "enabled")

    local fw_str="OFF"; [[ "$fw" -ge 1 ]] && fw_str="ON"
    local fv_str="OFF"; [[ "$fv" -ge 1 ]] && fv_str="ON"
    local sip_str="OFF"; [[ "$sip" -ge 1 ]] && sip_str="ON"
    local gk_str="OFF"; [[ "$gk" -ge 1 ]] && gk_str="ON"

    log "SEC  | Firewall: ${fw_str} | FileVault: ${fv_str} | SIP: ${sip_str} | Gatekeeper: ${gk_str}"

    # GitHub activity
    if [[ -n "$GITHUB_USER" ]]; then
        local gh_data=$(curl -s "https://github.com/users/${GITHUB_USER}/contributions" 2>/dev/null | python3 -c "
import sys, re
html = sys.stdin.read()
counts = re.findall(r'(\d+) contributions? on', html)
total = sum(int(c) for c in counts)
dates = re.findall(r'data-date=\"(\d{4}-\d{2}-\d{2})\".*?data-level=\"(\d)\"', html)
streak = 0
for d,l in reversed(dates):
    if int(l) > 0: streak += 1
    else: break
week = sum(int(l) > 0 for d,l in dates[-7:])
today_l = [l for d,l in dates if d == '$(date +%Y-%m-%d)']
today = today_l[0] if today_l else '0'
print(f'{total}|{streak}|{week}|{today}')
" 2>/dev/null)

        local gh_repos=$(curl -s "https://api.github.com/users/${GITHUB_USER}" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('public_repos',0))
" 2>/dev/null)

        local gh_events=$(curl -s "https://api.github.com/users/${GITHUB_USER}/events/public?per_page=30" 2>/dev/null | python3 -c "
import sys,json
from collections import Counter
events=json.load(sys.stdin)
repos=Counter()
recent=[]
for e in events:
    name=e['repo']['name'].split('/')[-1]
    repos[name]+=1
    if len(recent)<3:
        t=e['type']
        p=e.get('payload',{})
        msg=''
        if t=='PushEvent':
            cs=p.get('commits',[])
            if cs:
                msg=cs[-1].get('message','').split('\n')[0][:50]
            else:
                msg='Merge'
        elif t=='CreateEvent':
            ref=p.get('ref_type','')
            ref_name=p.get('ref','') or ''
            msg=f'Create {ref} {ref_name}'.strip()[:50]
        elif t=='PullRequestEvent':
            action=p.get('action','')
            pr=p.get('pull_request',{})
            title=pr.get('title','') or pr.get('head',{}).get('ref','')
            msg=f'PR {action}: {title}'[:50]
        elif t=='IssuesEvent':
            action=p.get('action','')
            title=p.get('issue',{}).get('title','')[:40]
            msg=f'Issue {action}: {title}'[:50]
        elif t=='DeleteEvent':
            ref=p.get('ref_type','')
            ref_name=p.get('ref','') or ''
            msg=f'Delete {ref} {ref_name}'.strip()[:50]
        else:
            msg=t.replace('Event','')
        msg=msg.replace(';','').replace('|','')
        recent.append(f'{msg}@{name}')
active=','.join(f'{r}({c})' for r,c in repos.most_common(3))
last3=';'.join(recent)
print(f'{active}|{last3}')
" 2>/dev/null)

        local gh_total=$(echo "$gh_data" | cut -d'|' -f1)
        local gh_streak=$(echo "$gh_data" | cut -d'|' -f2)
        local gh_week=$(echo "$gh_data" | cut -d'|' -f3)
        local gh_today=$(echo "$gh_data" | cut -d'|' -f4)
        local gh_active=$(echo "$gh_events" | cut -d'|' -f1)
        local gh_last3=$(echo "$gh_events" | cut -d'|' -f2)

        log "GH   | Year: ${gh_total:-0} | Streak: ${gh_streak:-0}d | Week: ${gh_week:-0}/7 | Today: ${gh_today:-0} | Repos: ${gh_repos:-0} | Active: ${gh_active} | Last3: ${gh_last3}"
    fi
}

# --- Run One Check Cycle ------------------------------------

run_check() {
    log "--- CHECK START ---"
    local latest="["

    # Check all websites
    for url in "${WEBSITES[@]}"; do
        local result
        result=$(check_website "$url")
        latest="$latest$result,"
    done

    # Check server
    local srv_result
    srv_result=$(check_server)
    if [[ -n "$srv_result" ]]; then
        latest="$latest$srv_result,"
    fi

    # Remove trailing comma & close array
    latest="${latest%,}]"
    echo "$latest" > "$LATEST_FILE"

    log "--- CHECK END ---"
}

# --- Daemon Loop --------------------------------------------

run_daemon() {
    while true; do
        run_check
        sleep "$CHECK_INTERVAL"
    done
}

# --- Commands -----------------------------------------------

case "${1:-once}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Monitor is already running (PID $(cat "$PID_FILE"))"
            exit 0
        fi
        echo "Starting monitor (interval: ${CHECK_INTERVAL}s)..."
        run_daemon &
        echo $! > "$PID_FILE"
        echo "Monitor started (PID $!)"
        echo "Log: $LOG_FILE"
        echo "View: ./monitor-view.sh"
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            local_pid=$(cat "$PID_FILE")
            if kill -0 "$local_pid" 2>/dev/null; then
                kill "$local_pid"
                rm -f "$PID_FILE"
                echo "Monitor stopped (PID $local_pid)"
            else
                rm -f "$PID_FILE"
                echo "Monitor was not running (stale PID file removed)"
            fi
        else
            echo "Monitor is not running"
        fi
        ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Monitor is RUNNING (PID $(cat "$PID_FILE"))"
            echo "Interval: ${CHECK_INTERVAL}s"
            echo "Websites: ${#WEBSITES[@]}"
            echo "Log: $LOG_FILE"
            if [[ -f "$LOG_FILE" ]]; then
                echo ""
                echo "Last check:"
                grep "CHECK END" "$LOG_FILE" | tail -1
            fi
        else
            echo "Monitor is NOT running"
        fi
        ;;
    once)
        echo "Running single check..."
        run_check
        echo "Done. Results in $LOG_FILE"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|once}"
        exit 1
        ;;
esac
