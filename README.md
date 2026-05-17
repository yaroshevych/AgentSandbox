# AgentSandbox

Sandbox AI coding agents in Docker — one command, per project. Pure one-line bash to generate.

Agents get your project directory and nothing else. No access to the rest of your filesystem. Optionally, no access to the broader internet. Everything else just works: agent credentials, AI provider endpoints, local dev tooling.

- Generates a project-local `Dockerfile` and `agents` script
- Supports Claude Code, Codex, Pi, and OpenCode, credentials shared from host
- Adds Python, Node, Go, or Rust tooling in container
- Mounts the repo read-only or writable
- Supports outbound firewall

```sh
cd your/project
curl -fsSL https://raw.githubusercontent.com/yaroshevych/AgentSandbox/main/install.sh | bash
./agents claude
```

## What it generates

Running the installer creates these files in your current directory:

| File | Purpose |
|------|---------|
| `Dockerfile` | Reproducible build for your agent environment |
| `agents` | Launcher — runs the agent in the container |
| `init-firewall.sh` | Network firewall (only generated when `--network block` is selected) |

## Supported agents

| Agent | Command |
|-------|---------|
| [Claude Code](https://claude.ai/code) | `./agents claude` |
| [Codex](https://github.com/openai/codex) | `./agents codex` |
| [Pi](https://earendil.works) | `./agents pi` |
| [OpenCode](https://opencode.ai) | `./agents opencode` |

## Supported stacks

`python` · `node` · `go` · `rust`

You can combine multiple agents and tech stacks. For example, you can use Claude for web development and Codex for backend work in a single project.

## Using the generated launcher

```sh
./agents           # drop into a shell inside the container
./agents claude    # launch Claude Code
./agents codex     # launch Codex
./agents pi        # launch Pi
./agents opencode  # launch OpenCode
```

The container image is built by the installer. If you change the `Dockerfile`, run `docker build -t agentsandbox .` to rebuild.

## Non-interactive install

If you have all your choices ready, bypass the wizard by passing flags:

```sh
curl -fsSL https://raw.githubusercontent.com/yaroshevych/AgentSandbox/main/install.sh | bash -s -- \
  --agent claude \
  --stack python \
  --network allow \
  --repo-access writable \
  --docker-access none \
  --persistence keep-agent-cache
```

`--agent` and `--stack` are repeatable for multi-agent / multi-stack setups.

## Generated isolation model

**Filesystem isolation** — the container mounts only the current directory, where `agents` is invoked. The agent cannot read or write anything outside it.

**Network isolation** — with `--network block`, outbound traffic is restricted to GitHub, npm, and the agent's API endpoint via an in-container `iptables` firewall. All other connections are rejected. The firewall verifies itself on startup and aborts if checks fail.

**Credentials and agent config** — API keys are mounted read-write from your host config directories (e.g. `~/.claude`, `~/.codex`).

**Inspectable output** — `install.sh` writes plain `Dockerfile`, `agents`, and optionally `init-firewall.sh` to your current directory. Read, edit, or commit them as you see fit.
