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

# ── dockerfile generator ───────────────────────────────────────────────────────

generate_dockerfile() {
    local agents="$1"
    local stacks="$2"
    local network="$3"

    local agent_list stack_list
    agent_list="$(echo "$agents" | tr ' ' '+')"
    if [ -n "$stacks" ]; then
        stack_list="$(echo "$stacks" | tr ' ' '+')"
        printf '# Container for %s / %s\n\n' "$agent_list" "$stack_list"
    else
        printf '# Container for %s\n\n' "$agent_list"
    fi

    [ "$network" = "offline" ] && \
        printf '# network_mode: none — container has no internet access at runtime\n\n'

    local need_go=0 need_rust=0
    for stack in $stacks; do
        [ "$stack" = "go" ]   && need_go=1
        [ "$stack" = "rust" ] && need_rust=1
    done

    cat <<'EOF'
FROM node:22-bookworm-slim

# All tool caches land in /cache — mount one named volume to persist across runs
EOF

    if [ "$need_rust" = "1" ]; then
        cat <<'EOF'
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_TARGET_DIR=/cache/cargo-target \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go/build \
    npm_config_cache=/cache/npm \
    PNPM_HOME=/cache/pnpm/home \
    XDG_CACHE_HOME=/cache/xdg \
    UV_CACHE_DIR=/cache/uv
EOF
    else
        cat <<'EOF'
ENV CARGO_TARGET_DIR=/cache/cargo-target \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go/build \
    npm_config_cache=/cache/npm \
    PNPM_HOME=/cache/pnpm/home \
    XDG_CACHE_HOME=/cache/xdg \
    UV_CACHE_DIR=/cache/uv
EOF
    fi

    printf '\nRUN apt-get update && apt-get install -y --no-install-recommends \\\n'
    printf '        git curl ca-certificates jq less unzip \\\n'
    printf '        ripgrep fd-find gh procps tmux'

    for stack in $stacks; do
        case "$stack" in
            python) printf ' \\\n        python3 python3-venv python3-pip' ;;
        esac
    done

    printf ' \\\n    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \\\n'
    printf '    && rm -rf /var/lib/apt/lists/*\n'

    if [ "$need_go" = "1" ]; then
        cat <<'EOF'

ARG GO_VERSION=1.23.4
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
        amd64) go_arch="amd64" ;; \
        arm64) go_arch="arm64" ;; \
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz
ENV PATH="/usr/local/go/bin:${PATH}"
EOF
    fi

    if [ "$need_rust" = "1" ]; then
        cat <<'EOF'

RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
    && chmod -R a+w "${CARGO_HOME}" "${RUSTUP_HOME}"
ENV PATH="${CARGO_HOME}/bin:${PATH}"
EOF
    fi

    cat <<'EOF'

RUN mkdir -p /cache /usr/local/share/npm-global \
    && chown node:node /cache /usr/local/share/npm-global

USER node

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH="/usr/local/share/npm-global/bin:/home/node/.claude/local:${PATH}"

EOF

    local npm_agents="" need_claude=0
    for agent in $agents; do
        case "$agent" in
            claude)   need_claude=1 ;;
            codex)    npm_agents="$npm_agents @openai/codex" ;;
            pi)       npm_agents="$npm_agents @earendil-works/pi-coding-agent" ;;
            opencode) npm_agents="$npm_agents opencode-ai" ;;
        esac
    done
    npm_agents="$(echo "$npm_agents" | sed 's/^ //')"

    [ -n "$npm_agents" ]    && printf 'RUN npm install -g %s\n' "$npm_agents"
    [ "$need_claude" = "1" ] && printf 'RUN curl -fsSL https://claude.ai/install.sh | bash\n'
}

# TODO: generate_agents_script

main() {
    require_command docker

    local agents="" stacks="" network="" repo_access="" docker_access="" persistence=""
    FORCE=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --agent)         agents="$agents $2";       shift 2 ;;
            --stack)         stacks="$stacks $2";       shift 2 ;;
            --network)       network="$2";              shift 2 ;;
            --repo-access)   repo_access="$2";          shift 2 ;;
            --docker-access) docker_access="$2";        shift 2 ;;
            --persistence)   persistence="$2";          shift 2 ;;
            --force)         FORCE=1;                   shift ;;
            *) die "Unknown flag: $1" ;;
        esac
    done

    agents="$(echo "$agents"       | tr -s ' ' | sed 's/^ //;s/ $//')"
    stacks="$(echo "$stacks"       | tr -s ' ' | sed 's/^ //;s/ $//')"

    # TODO: wizard for missing values
    # TODO: generate files

    [ -z "$agents" ] && die "At least one agent is required (--agent claude|codex|pi|opencode)."
    die "Generator not implemented yet."
}

main "$@"
