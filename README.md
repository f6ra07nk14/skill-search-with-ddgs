# search-with-ddgs

Install a local `search-with-ddgs` skill and a dedicated DDGS MCP runtime so your agent can fetch current web information through a target-local install boundary.

`install.sh` creates an isolated skill directory, provisions a local `.venv`, installs `ddgs[api,mcp]`, renders a single-file `SKILL.md` whose frontmatter description stays trigger-only, and prints the exact `mcpServers` JSON block to paste into your MCP client configuration.

The generated skill keeps a discovery-first `Overview`, `When to Use`, one `Workflow`, and `Common Mistakes`. Deeper DDGS quick-reference material is intentionally deferred to runtime tool inspection or current docs instead of inline generated tables.

[Quick start](#quick-start) • [What gets installed](#what-gets-installed) • [Generated skill contract](#generated-skillmd-contract) • [CLI options](#cli-options) • [Installer phases](#installer-phases) • [Troubleshooting](#troubleshooting) • [Maintainer verification](#maintainer-verification)

> [!NOTE]
> Supported platforms: macOS and Linux. The installer requires `uv` on your `PATH` before it can provision the skill-local environment.

## Why this repository exists

This project keeps the shipped DDGS integration reproducible and local to the installed skill:

- provisions DDGS into the skill-local `.venv/bin/ddgs` runtime
- emits the canonical `mcpServers` handoff for that installed runtime
- generates a single-file `SKILL.md` with a trigger-only description and discovery-first body sections
- defers deeper DDGS tool/argument reference to runtime tool inspection or current docs
- fails by phase, with targeted `ERROR` and `NEXT` guidance

## Quick start

### Default interactive install

```bash
bash install.sh
```

### Non-interactive install

```bash
bash install.sh --non-interactive
```

After the installer finishes:

1. Copy the final `mcpServers` JSON block into your MCP client configuration.
2. Keep the emitted `command` path exactly as printed.
3. Open the generated `SKILL.md` in the installed skill directory; it should keep a trigger-only description plus `Overview`, `When to Use`, one `Workflow`, and `Common Mistakes`.
4. For deeper DDGS argument/reference details, inspect the runtime tool surface or current docs instead of expecting inline tables in the generated skill.

> [!IMPORTANT]
> Treat the install as successful only when **both** of these signals appear:
>
> 1. the final `mcpServers` JSON block
> 2. the final completion line:
>
> ```text
> [phase:install] S04 install complete. Local ddgs environment is ready.
> ```

## What gets installed

By default, the installer writes to:

```text
~/.agents/skills/search-with-ddgs
```

A successful install produces a layout like this:

```text
~/.agents/skills/search-with-ddgs/
├── .venv/
│   └── bin/
│       └── ddgs
├── pyproject.toml
├── uv.lock          # copied when present, or retained if generated during sync
└── SKILL.md
```

What the installer does:

- resolves install settings from prompts, flags, or defaults
- checks platform support (`darwin` or `linux`)
- verifies `uv` is available
- creates the target skill directory
- copies repo metadata into that directory
- runs `uv sync --directory <target>`
- verifies the canonical executable at `.venv/bin/ddgs`
- renders the single-file `SKILL.md` contract with trigger-only frontmatter and discovery-first sections
- prints the canonical MCP handoff snippet

> [!TIP]
> The emitted MCP `command` should keep pointing at the installed skill-local executable path.

## Generated SKILL.md contract

The installed `SKILL.md` is intentionally small and stable:

- the YAML `description` stays trigger-only; it says when to load the skill, not the workflow to execute
- the body keeps `Overview`, `When to Use`, one `Workflow`, and `Common Mistakes`
- the canonical handoff remains the final `mcpServers` block whose `command` points at the installed `.venv/bin/ddgs`
- deeper DDGS quick-reference content is deferred to runtime tool inspection or current docs rather than inline generated tables
- drift back to duplicate sequence/reference sections or HTML table dumps is a contract bug

## Common install examples

### Install to the default skill root

```bash
bash install.sh
```

### Install to a different skill root

```bash
bash install.sh --skill-root ~/.claude/skills
```

### Use a custom skill directory and MCP server name

```bash
bash install.sh \
  --skill-root ~/.agents/skills \
  --skill-name search-with-ddgs-prod \
  --server-name ddgs-prod \
  --non-interactive
```

## CLI options

`bash install.sh --help` prints the current CLI contract and repeats the shipped skill shape:

```text
Usage: install.sh [options]

Installer entrypoint for the search-with-ddgs skill.
Renders a single-file SKILL.md whose frontmatter description stays trigger-only.
The generated body keeps Overview, When to Use, one Workflow, and Common Mistakes.
On success, the final mcpServers handoff points at the installed .venv/bin/ddgs path.
For deeper DDGS details, use runtime tool inspection or current docs instead of inline generated tables.

Options:
  --skill-root <path>      Skill install root (default: ~/.agents/skills)
  --skill-name <name>      Skill directory name (default: search-with-ddgs)
  --server-name <name>     MCP server name label (default: ddgs)
  --non-interactive        Disable prompts; resolve from flags + defaults only
  --help                   Show this help text
```

## Installer phases

The installer is phase-oriented. When something fails, start with the first `[phase:<name>] ERROR:` line.

| Phase | What it checks or does |
| --- | --- |
| `config` | Resolves flags, prompts, defaults, and normalized values |
| `platform` | Allows only macOS and Linux |
| `uv` | Detects `uv` and, in interactive mode, can guide the install path |
| `filesystem` | Resolves and creates the target directories safely |
| `metadata-copy` | Copies `pyproject.toml` and optional `uv.lock` into the target skill |
| `project-sync` | Runs `uv sync --directory <target>` |
| `executable-verification` | Verifies `.venv/bin/ddgs` exists and is executable |
| `template-render` | Renders `SKILL.md` with the selected skill name, server name, and executable path |
| `install` | Emits the final MCP handoff JSON and completion line |

## MCP handoff

The final output includes a block shaped like this:

```json
{
  "mcpServers": {
    "ddgs": {
      "command": "/absolute/path/to/search-with-ddgs/.venv/bin/ddgs",
      "args": ["mcp"]
    }
  }
}
```

Paste the emitted object under the top-level `mcpServers` key in your MCP client config.

## Troubleshooting

| Symptom | What it means | What to do |
| --- | --- | --- |
| `uv not found in PATH` | Prerequisite missing | Install `uv`, then rerun the installer |
| `Unsupported platform` | The installer only supports macOS and Linux | Run on a supported platform |
| `Target skill directory already exists` | The target path is already occupied | Choose a different `--skill-root` / `--skill-name`, or remove the existing directory |
| `uv sync failed` | Environment provisioning did not complete | Inspect the `project-sync` output, fix the target metadata or environment issue, then rerun |
| `Missing ddgs executable` or `ddgs path is not executable` | The local runtime was not provisioned correctly | Fix the sync step or permissions, then rerun in a clean target directory |
| `Template not found` / `Template file is not readable` | Installer source files are incomplete or unreadable | Restore `SKILL.md.jinja` or its permissions and rerun |
| No final JSON block or no completion line | Install did not complete | Treat the run as failed and fix the first phase error before retrying |

## Maintainer verification

Use these commands to verify the installer and its test suite:

```bash
bash -n install.sh
bash scripts/ensure_bats.sh
PATH="$PWD/.tools/bats/bin:$PATH" bats tests/test_documentation_contract.bats tests/test_install_preflight.bats
PATH="$PWD/.tools/bats/bin:$PATH" bats tests
```

Key files in this repository:

- `install.sh`
- `render_skill.py`
- `SKILL.md.jinja`
- `scripts/ensure_bats.sh`
- `tests/test_documentation_contract.bats`
- `tests/test_install_preflight.bats`
- `tests/test_install_project_sync.bats`
- `tests/test_install_environment.bats`
- `tests/test_skill_template_shape.bats`
