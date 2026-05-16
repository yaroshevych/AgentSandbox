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
  --network <allow|block>
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
        local example
        example="$(echo "$opts" | awk '{print $1, $2}')"
        printf '  %bExample:%b  %s\n' "${DIM}" "${RESET}" "$example" >"$TTY"
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

    if [ "$network" = "block" ]; then
        printf ' \\\n        sudo iptables ipset iproute2 dnsutils aggregate'
    fi

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

    if [ "$network" = "block" ]; then
        cat <<'EOF'

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh \
    && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
       > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall
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
    npm_agents="$(printf '%s' "$npm_agents" | sed 's/^ //')"

    if [ -n "$npm_agents" ]; then
        printf 'RUN npm install -g %s\n' "$npm_agents"
    fi
    if [ "$need_claude" = "1" ]; then
        printf 'RUN curl -fsSL https://claude.ai/install.sh | bash\n'
    fi
}

# ── firewall script generator ──────────────────────────────────────────────────

generate_firewall_script() {
    local agents="$1"

    local allowed_domains="registry.npmjs.org"
    for agent in $agents; do
        case "$agent" in
            claude)   allowed_domains="$allowed_domains api.anthropic.com statsig.anthropic.com statsig.com sentry.io" ;;
            codex)    allowed_domains="$allowed_domains api.openai.com" ;;
        esac
    done

    cat <<'EOF'
#!/bin/bash
# Network firewall — allows GitHub, npm, and agent API endpoints; blocks everything else
# Runs inside the container via: sudo /usr/local/bin/init-firewall.sh
set -euo pipefail
IFS=$'\n\t'

EOF

    printf 'ALLOWED_DOMAINS="%s"\n' "$allowed_domains"

    for agent in $agents; do
        case "$agent" in
            pi)       printf '# TODO: add Pi agent API domain to ALLOWED_DOMAINS\n' ;;
            opencode) printf '# TODO: add OpenCode API domain to ALLOWED_DOMAINS\n' ;;
        esac
    done

    cat <<'EOF'

DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127.0.0.11" || true)

iptables -F; iptables -X
iptables -t nat -F; iptables -t nat -X
iptables -t mangle -F; iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT  -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
[ -z "$gh_ranges" ] && { echo "ERROR: Failed to fetch GitHub IP ranges"; exit 1; }
while read -r cidr; do
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

for domain in $ALLOWED_DOMAINS; do
    echo "Resolving $domain..."
    while read -r ip; do
        ipset add allowed-domains "$ip" 2>/dev/null || true
    done < <(dig +noall +answer A "$domain" | awk '$4=="A"{print $5}')
done

HOST_IP=$(ip route | grep default | cut -d" " -f3)
HOST_NETWORK=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')

iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall active — GitHub, npm, and agent APIs allowed."
EOF
}

# ── agents script generator ────────────────────────────────────────────────────

generate_agents_script() {
    local agents="$1"
    local network="$2"
    local repo_access="$3"
    local docker_access="$4"
    local persistence="$5"

    cat <<'EOF'
#!/usr/bin/env bash
# Generated by AgentSandbox
set -euo pipefail

IMAGE=agentsandbox
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ensure_image() {
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "==> Building $IMAGE (first run — this takes a few minutes)..."
        docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
    fi
}

run() {
    ensure_image
    docker run --rm -it \
EOF

    if [ "$network" = "block" ]; then
        printf '        --cap-add NET_ADMIN \\\n'
    fi

    case "$repo_access" in
        writable) printf '        -v "$(pwd):/workspace:cached" \\\n' ;;
        readonly) printf '        -v "$(pwd):/workspace:ro,cached" \\\n' ;;
    esac

    case "$persistence" in
        keep-agent-cache|keep-workspace)
            printf '        -v agentsandbox-cache:/cache \\\n' ;;
    esac

    case "$docker_access" in
        docker-socket|docker-cli-only)
            printf '        -v /var/run/docker.sock:/var/run/docker.sock \\\n' ;;
    esac

    for agent in $agents; do
        case "$agent" in
            claude)
                printf '        -v "$HOME/.claude:/home/node/.claude:ro" \\\n'
                printf '        -v "$HOME/.claude.json:/home/node/.claude.json:ro" \\\n'
                ;;
            codex)
                printf '        -v "$HOME/.codex:/home/node/.codex:ro" \\\n'
                ;;
            pi)
                printf '        -v "$HOME/.pi:/home/node/.pi:ro" \\\n'
                ;;
            opencode)
                printf '        -v "$HOME/.opencode:/home/node/.opencode:ro" \\\n'
                printf '        -v "$HOME/.config/opencode:/home/node/.config/opencode:ro" \\\n'
                printf '        -v "$HOME/.local/share/opencode:/home/node/.local/share/opencode:ro" \\\n'
                printf '        -v "$HOME/.local/state/opencode:/home/node/.local/state/opencode:ro" \\\n'
                ;;
        esac
    done

    if [ "$network" = "block" ]; then
        cat <<'EOF'
        -w /workspace \
        "$IMAGE" bash -c 'sudo /usr/local/bin/init-firewall.sh && exec "$@"' -- "$@"
}
EOF
    else
        cat <<'EOF'
        -w /workspace \
        "$IMAGE" "$@"
}
EOF
    fi

    printf '\ncase "${1:-}" in\n'

    for agent in $agents; do
        case "$agent" in
            claude)   printf '    claude)   shift; run claude "$@" ;;\n' ;;
            codex)    printf '    codex)    shift; run codex "$@" ;;\n' ;;
            pi)       printf '    pi)       shift; run pi "$@" ;;\n' ;;
            opencode) printf '    opencode) shift; run opencode "$@" ;;\n' ;;
        esac
    done

    cat <<'EOF'
    shell|"") run bash ;;
    *)        echo "Warning: unknown command '$1', dropping into shell" >&2; run bash ;;
esac
EOF
}

# ── main ──────────────────────────────────────────────────────────────────────

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

    agents="$(echo "$agents" | tr -s ' ' | sed 's/^ //;s/ $//')"
    stacks="$(echo "$stacks"  | tr -s ' ' | sed 's/^ //;s/ $//')"

    local need_wizard=0
    [ -z "$agents" ]        && need_wizard=1
    [ -z "$network" ]       && need_wizard=1
    [ -z "$repo_access" ]   && need_wizard=1
    [ -z "$docker_access" ] && need_wizard=1
    [ -z "$persistence" ]   && need_wizard=1

    if [ "$need_wizard" = "1" ]; then
        check_tty

        printf '\n'
        say "AgentSandbox Setup"
        printf '\nGenerates a Dockerfile + agents launcher for AI coding agents.\n'

        if [ -z "$agents" ]; then
            multi_select agents \
                "Which agents?" \
                "claude codex pi opencode" \
                "1"
        fi

        if [ -z "$stacks" ]; then
            multi_select stacks \
                "Which language stacks? (optional)" \
                "python node go rust"
        fi

        if [ -z "$network" ]; then
            single_select network \
                "Network access inside the container?" \
                "allow block" \
                "allow"
        fi

        if [ -z "$repo_access" ]; then
            single_select repo_access \
                "Repository access?" \
                "writable readonly empty" \
                "writable"
        fi

        if [ -z "$docker_access" ]; then
            single_select docker_access \
                "Docker socket access?" \
                "none docker-cli-only docker-socket" \
                "none"
        fi

        if [ -z "$persistence" ]; then
            single_select persistence \
                "Agent cache persistence?" \
                "keep-agent-cache disposable" \
                "keep-agent-cache"
        fi

        printf '\n'
    fi

    [ -z "$agents" ] && die "At least one agent is required (--agent claude|codex|pi|opencode)."

    : "${network:=allow}"
    : "${repo_access:=writable}"
    : "${docker_access:=none}"
    : "${persistence:=keep-agent-cache}"

    backup_or_confirm_overwrite "Dockerfile"
    backup_or_confirm_overwrite "agents"
    if [ "$network" = "block" ]; then
        backup_or_confirm_overwrite "init-firewall.sh"
    fi

    say "Generating..."

    generate_dockerfile "$agents" "$stacks" "$network" > Dockerfile
    step "Dockerfile"

    generate_agents_script "$agents" "$network" "$repo_access" "$docker_access" "$persistence" > agents
    chmod +x agents
    step "agents"

    if [ "$network" = "block" ]; then
        generate_firewall_script "$agents" > init-firewall.sh
        chmod +x init-firewall.sh
        step "init-firewall.sh"
    fi

    printf '\n'
    say "Done."
    printf '\n'

    printf '  Start an agent (builds the image automatically on first run):\n\n'
    for agent in $agents; do
        printf '    ./agents %s\n' "$agent"
    done
    printf '\n'

    printf '  Or drop into a shell:\n\n'
    printf '    ./agents shell\n\n'

    printf '  Credentials mounted read-only from your host:\n\n'
    for agent in $agents; do
        case "$agent" in
            claude)   printf '    Claude   → ~/.claude  ~/.claude.json\n' ;;
            codex)    printf '    Codex    → ~/.codex\n' ;;
            pi)       printf '    Pi       → ~/.pi\n' ;;
            opencode) printf '    OpenCode → ~/.opencode  ~/.config/opencode\n' ;;
        esac
    done
    printf '\n'

    if [ "$network" = "block" ]; then
        printf '  Network: blocked — GitHub, npm, and agent APIs only.\n'
        printf '  Firewall runs inside the container on each launch.\n\n'
    fi
}

main "$@"
