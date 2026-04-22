# skill-search-with-ddgs

Empowering AI Agents with the skill to execute web searches by invoking DDGS via MCP tools.

## Installer entrypoint

This repository now includes a shell installer entrypoint:

- `install.sh`

Current S04 scope is **preflight + local environment provisioning + rendered skill artifact + MCP handoff output**: it resolves installer config values, checks platform + `uv`, creates `<skill_root>/<skill_name>/.venv`, installs `ddgs[api,mcp]` into that local environment, verifies `<skill_root>/<skill_name>/.venv/bin/ddgs`, renders `<skill_root>/<skill_name>/SKILL.md` from the repo-local `SKILL.md.jinja` template, and then emits one copy-ready MCP snippet before reporting install completion.

### Preflight requirements and behavior

- Supported platforms: **macOS** (`darwin`) and **Linux** (`linux`) only.
- `uv` must be available on `PATH` before installer work can proceed.
- If `uv` is missing, the installer prints official install guidance for both commands:
  - `curl -LsSf https://astral.sh/uv/install.sh | sh`
  - `wget -qO- https://astral.sh/uv/install.sh | sh`
- In interactive mode, the installer can run a guided `uv` install after explicit confirmation (`y`/`yes`), then immediately re-check `uv`.
- In non-interactive mode (`--non-interactive`), missing `uv` is always a fatal preflight error.
- Any unsupported platform, failed install attempt, or failed post-install re-check exits with a phase-prefixed error and a next-step message.

### Rendered `SKILL.md` contract

- Source template: repo-local `SKILL.md.jinja`.
- Destination artifact: `<skill_root>/<skill_name>/SKILL.md`.
- The rendered artifact uses the official skills format: YAML frontmatter followed by markdown section headings (not legacy wrapper tags).
- Injected values include:
  - selected `--server-name`
  - concrete local executable path `<skill_root>/<skill_name>/.venv/bin/ddgs`
- Workflow-first contract: MCP-first guidance appears before references (`mcp_servers` availability check first), DDGS Quick Reference material follows under `## References`, and fallback disclosure is explicit when DDGS is unavailable or weak.
- The DDGS Quick Reference content includes the tools table, shared parameters/defaults, `extract_content` format reference, and backend support matrix.
- Render failures are phase-scoped (`[phase:template-render]`) and fail fast before install completion output.

### Final MCP handoff output

On successful completion only (after executable verification and template rendering), the installer prints exactly one copy-ready JSON block that you can paste into your MCP configuration:

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

Contract details:

- `<server_name>` is the selected `--server-name` value.
- `command` is the resolved skill-local executable path.
- `args` is always `["mcp"]`.
- Any preflight/install/render failure exits before this snippet is emitted, so snippet absence is a trustworthy failure signal.

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
- `bash tests/test_install_preflight.sh` (preflight guardrails remain side-effect free)
- `bash tests/test_install_environment.sh` (authoritative install-boundary regression harness for rendered `SKILL.md`: verifies official skills format heading order, workflow MCP-first-to-fallback sequence, DDGS Quick Reference key table/section presence, and absence of legacy XML-like markers such as `<objective>`/`<required_sequence>`)

