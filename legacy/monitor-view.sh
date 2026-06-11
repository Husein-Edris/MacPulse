#!/bin/bash
# ============================================================
#  MONITOR VIEWER — Full-width Terminal Dashboard
#  Usage: ./monitor-view.sh          (one-time view)
#         ./monitor-view.sh live     (auto-refresh every 30s)
#         ./monitor-view.sh log      (tail the raw log)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# --- Colors -------------------------------------------------
R='\033[0;31m'    G='\033[0;32m'    Y='\033[0;33m'
B='\033[0;34m'    C='\033[0;36m'    M='\033[0;35m'
WH='\033[1;37m'   DIM='\033[2m'     BOLD='\033[1m'
NC='\033[0m'

# --- Layout -------------------------------------------------
COLS=$(tput cols 2>/dev/null || echo 80)
[[ $COLS -gt 120 ]] && COLS=120   # cap for readability
HALF=$(( (COLS - 6) / 2 ))        # each column width
PAD=2                              # indent

# --- Helpers ------------------------------------------------

sep() {
    printf "  ${DIM}"
    printf '%*s' $((COLS - 4)) '' | tr ' ' '─'
    printf "${NC}\n"
}

draw_bar() {
    local pct=${1:-0}
    local color=${2:-$G}
    local width=${3:-20}
    local filled=$(( pct * width / 100 ))
    [[ $filled -gt $width ]] && filled=$width
    local empty=$(( width - filled ))
    printf "${color}"
    printf '%*s' "$filled" '' | tr ' ' '▓'
    printf "${DIM}"
    printf '%*s' "$empty" '' | tr ' ' '░'
    printf "${NC}"
}

short_url() {
    echo "$1" | sed -E 's|https?://||' | sed 's|www\.||' | sed 's|/$||'
}

time_ago() {
    local ts="$1"
    local then_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$ts" "+%s" 2>/dev/null)
    local now_epoch=$(date "+%s")
    if [[ -z "$then_epoch" ]]; then echo "$ts"; return; fi
    local diff=$(( now_epoch - then_epoch ))
    if [[ $diff -lt 60 ]]; then echo "${diff}s ago"
    elif [[ $diff -lt 3600 ]]; then echo "$(( diff / 60 ))m ago"
    elif [[ $diff -lt 86400 ]]; then echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m ago"
    else echo "$(( diff / 86400 ))d ago"
    fi
}

next_check() {
    local ts="$1"
    local then_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$ts" "+%s" 2>/dev/null)
    local now_epoch=$(date "+%s")
    if [[ -z "$then_epoch" ]]; then echo "unknown"; return; fi
    local next_epoch=$(( then_epoch + CHECK_INTERVAL ))
    local diff=$(( next_epoch - now_epoch ))
    if [[ $diff -le 0 ]]; then echo "any moment"
    elif [[ $diff -lt 60 ]]; then echo "in ${diff}s"
    else echo "in $(( diff / 60 ))m"
    fi
}

# Move cursor to column N
col() { printf "\033[${1}G"; }

# --- Dashboard ----------------------------------------------

show_dashboard() {
    local now=$(date '+%Y-%m-%d %H:%M:%S')
    local col2_start=$(( PAD + HALF + 4 ))  # right column start

    # Buffer all output, then clear+print at once (no flash)
    local buf
    buf=$(_render_dashboard "$now" "$col2_start")
    printf '\033[H\033[J'
    printf '%s' "$buf"
}

_render_dashboard() {
    local now="$1"
    local col2_start="$2"

    # ===== HEADER =====
    printf "  ${BOLD}${C}SYSTEM MONITOR${NC}"
    col $((COLS - 19))
    printf "${DIM}%s${NC}\n" "$now"
    sep

    # ===== STATUS LINE =====
    local last_check_ts=""
    local last_check_line=$(grep "CHECK END" "$LOG_FILE" 2>/dev/null | tail -1)
    if [[ -n "$last_check_line" ]]; then
        last_check_ts=$(echo "$last_check_line" | grep -o '\[.*\]' | tr -d '[]')
    fi

    if [[ -f "$SCRIPT_DIR/.monitor.pid" ]] && kill -0 "$(cat "$SCRIPT_DIR/.monitor.pid")" 2>/dev/null; then
        local interval_min=$(( CHECK_INTERVAL / 60 ))
        printf "  ${G}●${NC} ${BOLD}Active${NC}  ${DIM}checking every ${interval_min} min${NC}"
    else
        printf "  ${R}●${NC} ${BOLD}Stopped${NC}  ${DIM}run: monitor-start${NC}"
    fi
    if [[ -n "$last_check_ts" ]]; then
        local ago=$(time_ago "$last_check_ts")
        local nxt=$(next_check "$last_check_ts")
        col $((COLS / 2))
        printf "${DIM}last:${NC} ${BOLD}%s${NC}  ${DIM}next:${NC} ${BOLD}%s${NC}" "$ago" "$nxt"
    fi
    printf "\n"

    # ===== SERVER SECTION =====
    if [[ "$MONITOR_SERVER" == "yes" ]] && [[ -f "$LOG_FILE" ]]; then
        local srv_line=$(grep "SRV " "$LOG_FILE" | tail -1)

        if [[ -n "$srv_line" ]]; then
            local cpu=$(echo "$srv_line" | grep -o 'CPU: [^|]*' | sed 's/CPU: //')
            local ram=$(echo "$srv_line" | grep -o 'RAM: [^|]*' | sed 's/RAM: //')
            local load=$(echo "$srv_line" | grep -o 'Load: [^|]*' | sed 's/Load: //')
            local disk=$(echo "$srv_line" | grep -o 'Disk: [^|]*' | sed 's/Disk: //')
            local up=$(echo "$srv_line" | grep -o 'Up: .*' | sed 's/Up: //')

            # CPU values
            local cpu_val=$(echo "$cpu" | grep -o '^[0-9.]*')
            local cpu_cores=$(echo "$cpu" | grep -o '[0-9]* cores' | grep -o '[0-9]*')
            cpu_cores=${cpu_cores:-1}
            local cpu_int=${cpu_val%.*}
            [[ "$cpu_int" -gt 100 ]] && cpu_int=100
            local cc=$G; [[ "$cpu_int" -ge 50 ]] && cc=$Y; [[ "$cpu_int" -ge 80 ]] && cc=$R

            # RAM values
            local ram_pct=$(echo "$ram" | grep -o '[0-9.]*%' | tr -d '%')
            local ram_int=${ram_pct%.*}
            local rc=$G; [[ "$ram_int" -ge 60 ]] && rc=$Y; [[ "$ram_int" -ge 80 ]] && rc=$R

            # Disk values
            local disk_pct=$(echo "$disk" | grep -o '[0-9.]*%' | head -1 | tr -d '%')
            local disk_int=${disk_pct%.*}
            disk_int=${disk_int:-0}
            local dc=$G; [[ "$disk_int" -ge 70 ]] && dc=$Y; [[ "$disk_int" -ge 85 ]] && dc=$R

            local bar_w=$(( HALF / 3 ))
            [[ $bar_w -gt 25 ]] && bar_w=25
            [[ $bar_w -lt 12 ]] && bar_w=12

            # --- LEFT: CPU + RAM + DISK bars ---
            # --- RIGHT: Load + Uptime + Summary ---

            # Row 1: CPU (left) | LOAD (right)
            printf "  ${DIM}CPU${NC}  "
            draw_bar "$cpu_int" "$cc" "$bar_w"
            printf "  ${cc}%s%%${NC} ${DIM}/ %s cores${NC}" "$cpu_val" "$cpu_cores"
            col "$col2_start"
            printf "${DIM}LOAD${NC}     %s\n" "$load"

            # Row 2: RAM (left) | UPTIME (right)
            printf "  ${DIM}RAM${NC}  "
            draw_bar "$ram_int" "$rc" "$bar_w"
            printf "  ${rc}%s${NC}" "$ram"
            col "$col2_start"
            printf "${DIM}UPTIME${NC}   %s\n" "$up"

            # Row 3: DISK (left) | empty (right)
            printf "  ${DIM}DISK${NC} "
            draw_bar "$disk_int" "$dc" "$bar_w"
            printf "  ${dc}%s${NC}" "$disk"
            printf "\n"

            sep
        fi
    fi

    # ===== TOP PROCESSES =====
    local proc_line=$(grep "PROC " "$LOG_FILE" 2>/dev/null | tail -1)
    if [[ -n "$proc_line" ]]; then
        local proc_cpu=$(echo "$proc_line" | grep -o 'CPU: [^|]*' | sed 's/CPU: //')
        local proc_ram=$(echo "$proc_line" | grep -o 'RAM: .*' | sed 's/RAM: //')

        printf "  ${BOLD}${WH}TOP PROCESSES${NC}\n"
        printf "  ${DIM}CPU${NC}   "
        IFS=',' read -ra cpu_procs <<< "$proc_cpu"
        for p in "${cpu_procs[@]}"; do
            local pname=$(echo "$p" | sed -E 's/ [0-9]+%.*//')
            local ppct=$(echo "$p" | grep -oE '[0-9]+%')
            local pc=$G; local pv=${ppct%\%}
            [[ "${pv:-0}" -ge 30 ]] 2>/dev/null && pc=$Y
            [[ "${pv:-0}" -ge 60 ]] 2>/dev/null && pc=$R
            printf "${pc}%-14s %s${NC}  " "$pname" "$ppct"
        done
        printf "\n"
        printf "  ${DIM}RAM${NC}   "
        IFS=',' read -ra ram_procs <<< "$proc_ram"
        for p in "${ram_procs[@]}"; do
            local pname=$(echo "$p" | sed -E 's/ [0-9.]+%.*//')
            local ppct=$(echo "$p" | grep -oE '[0-9.]+%')
            printf "%-14s %s  " "$pname" "$ppct"
        done
        printf "\n"
        sep
    fi

    # ===== GITHUB =====
    local gh_line=$(grep "GH " "$LOG_FILE" 2>/dev/null | tail -1)
    if [[ -n "$gh_line" ]]; then
        local gh_year=$(echo "$gh_line" | grep -o 'Year: [0-9]*' | grep -o '[0-9]*')
        local gh_streak=$(echo "$gh_line" | grep -o 'Streak: [0-9]*' | grep -o '[0-9]*')
        local gh_week=$(echo "$gh_line" | grep -o 'Week: [0-9]*/7' | head -1 | sed 's/Week: //')
        local gh_today=$(echo "$gh_line" | grep -o 'Today: [0-9]*' | grep -o '[0-9]*')
        local gh_repos=$(echo "$gh_line" | grep -o 'Repos: [0-9]*' | grep -o '[0-9]*')
        local gh_commits=$(echo "$gh_line" | grep -o 'Recent commits: [0-9]*' | grep -o '[0-9]*')
        local gh_active=$(echo "$gh_line" | sed 's/.*Active: //' | sed 's/ | Last3.*//')
        local gh_last3=$(echo "$gh_line" | grep -o 'Last3: .*' | sed 's/Last3: //')

        printf "  ${BOLD}${WH}GITHUB${NC}  ${DIM}@${GITHUB_USER}${NC}\n"
        printf "  ${G}${gh_year:-0}${NC} contributions this year"
        col "$col2_start"
        printf "${DIM}repos:${NC} %s  ${DIM}streak:${NC} ${BOLD}%sd${NC}\n" "${gh_repos:-0}" "${gh_streak:-0}"
        if [[ -n "$gh_last3" ]]; then
            IFS=';' read -ra commit_entries <<< "$gh_last3"
            for entry in "${commit_entries[@]}"; do
                local cmsg=$(echo "$entry" | sed 's/@[^@]*$//')
                local crepo=$(echo "$entry" | grep -o '@[^@]*$' | sed 's/@//')
                printf "  ${C}%-40s${NC} ${DIM}%s${NC}\n" "$cmsg" "$crepo"
            done
        fi
        sep
    fi

    # ===== SECURITY =====
    local sec_line=$(grep "SEC " "$LOG_FILE" 2>/dev/null | tail -1)
    if [[ -n "$sec_line" ]]; then
        local fw=$(echo "$sec_line" | grep -o 'Firewall: [A-Z]*' | sed 's/Firewall: //')
        local fv=$(echo "$sec_line" | grep -o 'FileVault: [A-Z]*' | sed 's/FileVault: //')
        local sip=$(echo "$sec_line" | grep -o 'SIP: [A-Z]*' | sed 's/SIP: //')
        local gk=$(echo "$sec_line" | grep -o 'Gatekeeper: [A-Z]*' | sed 's/Gatekeeper: //')

        printf "  ${BOLD}${WH}SECURITY${NC}\n"

        # Firewall
        if [[ "$fw" == "ON" ]]; then
            printf "  ${G}●${NC} Firewall         ${G}ON${NC}"
        else
            printf "  ${R}●${NC} Firewall         ${R}OFF${NC}"
        fi
        col "$col2_start"
        # SIP
        if [[ "$sip" == "ON" ]]; then
            printf "${G}●${NC} SIP              ${G}ON${NC}\n"
        else
            printf "${R}●${NC} SIP              ${R}OFF${NC}\n"
        fi

        # FileVault
        if [[ "$fv" == "ON" ]]; then
            printf "  ${G}●${NC} FileVault        ${G}ON${NC}"
        else
            printf "  ${R}●${NC} FileVault        ${R}OFF${NC}"
        fi
        col "$col2_start"
        # Gatekeeper
        if [[ "$gk" == "ON" ]]; then
            printf "${G}●${NC} Gatekeeper       ${G}ON${NC}\n"
        else
            printf "${R}●${NC} Gatekeeper       ${R}OFF${NC}\n"
        fi
        sep
    fi

    # ===== WEBSITES =====
    local site_lines=$(grep "SITE " "$LOG_FILE" 2>/dev/null | tail -${#WEBSITES[@]})
    local site_count=${#WEBSITES[@]}
    local up_count=0 down_count=0
    if [[ -n "$site_lines" ]]; then
        up_count=$(echo "$site_lines" | grep -c "| UP |" || true)
        down_count=$(echo "$site_lines" | grep -c "| DOWN |" || true)
    fi

    printf "  ${BOLD}${WH}WEBSITES${NC}"
    if [[ $down_count -gt 0 ]]; then
        printf "  ${G}%s up${NC}  ${R}%s down${NC}" "$up_count" "$down_count"
    else
        printf "  ${G}all %s up${NC}" "$site_count"
    fi
    printf "\n"

    if [[ -n "$site_lines" ]]; then
        # Column positions (cursor-based so always aligned)
        local C_CODE=35
        local C_SPEED=42

        while IFS= read -r line; do
            local status=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
            local code=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            local rtime=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
            local url=$(short_url "$(echo "$line" | awk -F'|' '{print $5}' | xargs)")

            local sc=$G; [[ "$status" != "UP" ]] && sc=$R
            local cc=$G; [[ "$code" -ge 300 ]] 2>/dev/null && cc=$Y; [[ "$code" -ge 400 ]] 2>/dev/null && cc=$R; [[ "$code" == "000" ]] && cc=$R
            local tv=$(echo "$rtime" | tr -d 'ms')
            local tc=$G; [[ "$tv" -ge 800 ]] 2>/dev/null && tc=$Y; [[ "$tv" -ge 2000 ]] 2>/dev/null && tc=$R

            printf "  ${sc}●${NC} %s" "$url"
            col $C_CODE
            printf "${cc}%s${NC}" "$code"
            col $C_SPEED
            printf "${tc}%s${NC}\n" "$rtime"
        done <<< "$site_lines"
    else
        printf "  ${DIM}No data yet. Run: ./monitor.sh once${NC}\n"
    fi
    # ===== INCIDENTS =====
    local recent_downs=$(grep "SITE.*DOWN" "$LOG_FILE" 2>/dev/null | tail -5)
    if [[ -n "$recent_downs" ]]; then
        sep
        printf "  ${R}${BOLD}INCIDENTS${NC}\n"
        while IFS= read -r line; do
            local ts=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            local url=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
            local code=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            local display_url=$(short_url "$url")
            printf "  ${R}●${NC} ${DIM}%s${NC}  %-28s  ${R}HTTP %s${NC}\n" "$ts" "$display_url" "$code"
        done <<< "$recent_downs"
    fi

    # ===== FOOTER =====
    sep
    printf "  ${DIM}monitor-start | monitor-stop | monitor-status | monitor${NC}\n"
}

# --- Commands -----------------------------------------------

case "${1:-view}" in
    view)
        show_dashboard
        ;;
    live)
        while true; do
            show_dashboard
            printf "  ${DIM}Refreshing every 30s... Ctrl+C to exit${NC}\n"
            sleep 30
        done
        ;;
    log)
        if [[ -f "$LOG_FILE" ]]; then
            tail -f "$LOG_FILE"
        else
            echo "No log file yet. Run: ./monitor.sh once"
        fi
        ;;
    *)
        echo "Usage: $0 {view|live|log}"
        exit 1
        ;;
esac
