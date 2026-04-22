# skill-search-with-ddgs

Install a local `search-with-ddgs` skill so your agent can fetch current web information through an MCP server backed by DDGS.

## What this installs

Running the installer sets up a skill-local runtime (by default under `~/.agents/skills/search-with-ddgs`) and prepares the MCP handoff:

- creates a new skill directory
- creates a local `.venv`
- installs `ddgs[api,mcp]` into that environment
- verifies the local `ddgs` executable
- renders a generated `SKILL.md` for post-install usage guidance
- prints a copy-ready `mcpServers` JSON block

## Prerequisite

You need `uv` on your `PATH` before install. If `uv` is missing, the installer prints official install commands and stops before changing anything in non-interactive mode.

## Quick start

```bash
bash install.sh
```

Optional flags are available (`--skill-root`, `--skill-name`, `--server-name`, `--non-interactive`), but `bash install.sh` is the shortest truthful first run.

## What success looks like

Treat install as successful only when you see both of these outputs:

1. A final MCP handoff block with `mcpServers`, for example:

```json
{
  "mcpServers": {
    "<server_name>": {
      "command": "<skill_root>/<skill_name>/.venv/bin/ddgs",
      "args": ["mcp"]
    }
  }
}
```

2. The final completion line:

```text
[phase:install] S04 install complete. Local ddgs environment is ready.
```

If either signal is missing, treat the run as failed and follow the phase-specific error output.

## MCP handoff

Paste the emitted JSON under `mcpServers` in your MCP client configuration. Keep the generated `command` path and `args: ["mcp"]` exactly as emitted by the installer.

## Use the installed skill

After install, open the generated `SKILL.md` inside the installed skill directory and follow it when a task needs current information (web search, news search, or reading a known URL).

Example prompt that fits this skill:

- “What changed this week in major AI model releases? Include sources.”

Use the generated `SKILL.md` as the detailed behavior contract for tool order, fallback disclosure, and response requirements.

## Troubleshooting

- **`uv` not found**: install `uv`, then rerun `bash install.sh`.
- **Target skill directory already exists**: choose a different `--skill-root`/`--skill-name`, or remove the existing directory before rerunning.
- **No `mcpServers` block or no final completion line**: the install did not complete; fix the reported phase error and rerun.

## Maintainer reference

- `install.sh`
- `SKILL.md.jinja`
- `tests/test_install_preflight.sh`
- `tests/test_install_environment.sh`
