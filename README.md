# AgentSandbox

One command launches a shell wizard that generates hardened, inspectable Docker sandboxes for AI coding agents.

```sh
curl -fsSL https://agentsandbox.dev/install.sh | sh
./agents claude
```

## What it generates

Running the installer creates two files in your current directory:

| File | Purpose |
|------|---------|
| `Dockerfile` | Reproducible build for your agent environment |
| `agents` | Launcher — builds the image on first run, then runs the agent |

## Supported agents

| Agent | Command |
|-------|---------|
| [Claude Code](https://claude.ai/code) | `./agents claude` |
| [Codex](https://github.com/openai/codex) | `./agents codex` |
| [Pi](https://earendil.works) | `./agents pi` |
| [OpenCode](https://opencode.ai) | `./agents opencode` |

## Supported stacks

`python` · `node` · `go` · `rust`

Mix freely — select multiple stacks and the installer handles the Dockerfile layers.

## Usage

```sh
./agents           # drop into a shell inside the container
./agents claude    # launch Claude Code
./agents codex     # launch Codex
./agents pi        # launch Pi
./agents opencode  # launch OpenCode
```

The container image builds automatically the first time you run `./agents`.

## Non-interactive install

If you have all choices ready, bypass the wizard by passing flags:

```sh
curl -fsSL https://agentsandbox.dev/install.sh | sh -s -- \
  --agent claude \
  --stack python \
  --network full \
  --repo-access writable \
  --docker-access none \
  --persistence keep-agent-cache
```

`--agent` and `--stack` are repeatable for multi-agent / multi-stack setups.

## Security

The installer never:
- runs `sudo`
- installs anything globally
- modifies files outside the current directory
- runs Docker or any agent automatically

Inspect before running:

```sh
curl -fsSL https://agentsandbox.dev/install.sh        # read it
curl -fsSL https://agentsandbox.dev/install.sh | sh   # then run it
```

## Examples

See [`examples/`](examples/) for pre-generated configurations:

- [`mixed-all/`](examples/mixed-all/) — all four agents, all stacks
- [`rust-claude/`](examples/rust-claude/) — Claude + Rust
- [`python-codex-offline/`](examples/python-codex-offline/) — Codex + Python, air-gapped

## License

MIT
