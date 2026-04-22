# skill-search-with-ddgs

Empowering AI Agents with the skill to execute web searches by invoking DDGS via MCP tools.

## Installer entrypoint

This repository now includes a shell installer entrypoint:

- `install.sh`

Current S01 scope is **preflight-only**: it resolves installer config values and checks platform + `uv` prerequisites before any filesystem mutation.

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

