# skill-search-with-ddgs

Empowering AI Agents with the skill to execute web searches by invoking DDGS via MCP tools.

## Installer entrypoint

This repository now includes a shell installer entrypoint:

- `install.sh`

Current S02 scope is **preflight + local environment provisioning**: it resolves installer config values, checks platform + `uv`, creates `<skill_root>/<skill_name>/.venv`, installs `ddgs[api,mcp]` into that local environment, and verifies `<skill_root>/<skill_name>/.venv/bin/ddgs` before reporting success.

### Preflight requirements and behavior

- Supported platforms: **macOS** (`darwin`) and **Linux** (`linux`) only.
- `uv` must be available on `PATH` before installer work can proceed.
- If `uv` is missing, the installer prints official install guidance for both commands:
  - `curl -LsSf https://astral.sh/uv/install.sh | sh`
  - `wget -qO- https://astral.sh/uv/install.sh | sh`
- In interactive mode, the installer can run a guided `uv` install after explicit confirmation (`y`/`yes`), then immediately re-check `uv`.
- In non-interactive mode (`--non-interactive`), missing `uv` is always a fatal preflight error.
- Any unsupported platform, failed install attempt, or failed post-install re-check exits with a phase-prefixed error and a next-step message.

### CLI contract

```bash
bash install.sh [--skill-root <path>] [--skill-name <name>] [--server-name <name>] [--non-interactive] [--help]
```

Defaults:

- `--skill-root`: `~/.agents/skills`
- `--skill-name`: `search-with-ddgs`
- `--server-name`: `ddgs`

Verification harness:

- `bash -n install.sh`
- `bash tests/test_install_preflight.sh`
- `bash tests/test_install_environment.sh`

