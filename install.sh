#!/usr/bin/env bash
# AgentSandbox — generates a Dockerfile + agents launcher for AI coding agents
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
DIM='\033[2m'
RESET='\033[0m'

say()  { printf "${GREEN}==>${RESET} ${BOLD}%s${RESET}\n" "$*"; }
step() { printf "    ${DIM}created${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}warn:${RESET} %s\n" "$*" >&2; }
die()  { printf "${RED}error:${RESET} %s\n" "$*" >&2; exit 1; }

TTY=/dev/tty

# ── tty guard ─────────────────────────────────────────────────────────────────

check_tty() {
    [ -c "$TTY" ] || die \
"No interactive terminal. Run in a terminal, or pass all flags to skip the wizard:
  --agent <claude|codex|pi|opencode>  (repeatable)
  --network <full|offline>
  --repo-access <writable|readonly|empty>
  --docker-access <none|docker-cli-only|docker-socket>
  --persistence <keep-agent-cache|disposable>"
}

# ── prompt helpers ─────────────────────────────────────────────────────────────

multi_select() {
    local var="$1" msg="$2" opts="$3" required="${4:-0}"
    while true; do
        printf '\n%b%s%b\n' "${BOLD}" "$msg" "${RESET}" >"$TTY"
        printf '  %bOptions:%b  %s\n' "${DIM}" "${RESET}" "$opts" >"$TTY"
        printf '  %bExample:%b  %s\n' "${DIM}" "${RESET}" \
            "$(echo "$opts" | awk '{print $1, $2}')" >"$TTY"
        [ "$required" = "0" ] && \
            printf '  %b(press Enter to skip)%b\n' "${DIM}" "${RESET}" >"$TTY"
        printf '> ' >"$TTY"
        local val
        IFS= read -r val <"$TTY"
        val="$(echo "$val" | tr ',' ' ' | tr -s ' ' | sed 's/^ //;s/ $//')"
        if [ "$required" = "1" ] && [ -z "$val" ]; then
            warn "At least one selection is required."
            continue
        fi
        [ -z "$val" ] && break
        local ok=1
        for tok in $val; do
            local found=0
            for opt in $opts; do
                [ "$tok" = "$opt" ] && found=1 && break
            done
            if [ "$found" = "0" ]; then
                warn "Unknown option: '$tok'. Choose from: $opts"
                ok=0
                break
            fi
        done
        [ "$ok" = "1" ] && break
    done
    printf -v "$var" '%s' "$val"
}

single_select() {
    local var="$1" msg="$2" opts="$3" default="${4:-}"
    while true; do
        printf '\n%b%s%b\n' "${BOLD}" "$msg" "${RESET}" >"$TTY"
        local i=1
        for opt in $opts; do
            if [ "$opt" = "$default" ]; then
                printf '  %d) %s %b(default)%b\n' "$i" "$opt" "${DIM}" "${RESET}" >"$TTY"
            else
                printf '  %d) %s\n' "$i" "$opt" >"$TTY"
            fi
            i=$((i+1))
        done
        printf '> ' >"$TTY"
        local val
        IFS= read -r val <"$TTY"
        [ -z "$val" ] && val="$default"
        local found="" j=1
        for opt in $opts; do
            if [ "$val" = "$opt" ] || [ "$val" = "$j" ]; then
                found="$opt"; break
            fi
            j=$((j+1))
        done
        if [ -n "$found" ]; then
            printf -v "$var" '%s' "$found"
            break
        fi
        warn "Invalid choice. Enter a name or number."
    done
}

confirm() {
    local msg="$1" default="${2:-y}"
    local hint="[Y/n]"
    [ "$default" = "n" ] && hint="[y/N]"
    printf '%b%s%b %s: ' "${BOLD}" "$msg" "${RESET}" "$hint" >"$TTY"
    local val
    IFS= read -r val <"$TTY"
    [ -z "$val" ] && val="$default"
    case "$val" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

backup_or_confirm_overwrite() {
    local path="$1"
    [ ! -e "$path" ] && return 0
    [ "${FORCE:-0}" = "1" ] && return 0
    confirm "'$(basename "$path")' already exists. Overwrite?" "n" || die "Aborted."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "Required command not found: '$1'. Please install it and retry."
}

# TODO: generate_dockerfile
# TODO: generate_agents_script
# TODO: main

main() {
    require_command docker
    die "Not implemented yet."
}

main "$@"
