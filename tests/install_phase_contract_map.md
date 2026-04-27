# Install phase contract map

This file is T01's per-scenario source of truth for the S02 phase-based installer suite cleanup in `M006-nxnvwf`.
It inventories every currently tracked `@test` from:

- `tests/test_install_preflight.bats`
- `tests/test_install_environment.bats`
- `tests/test_install_project_sync.bats`
- `tests/test_skill_template_shape.bats`
- `tests/test_documentation_contract.bats`

It follows D033-D037:

- keep the maintained Bats surface installer-contract-only;
- regroup kept scenarios by the same `install.sh` phase boundaries exposed in runtime diagnostics;
- prefer semantic phase anchors over exact README/help wording freezes;
- keep direct placeholder/runtime-value assertions helper-owned in `tests/test_skill_template_shape.bats`; and
- preserve documentation wording checks only as deferred S03 reference work, not as maintained `tests/*.bats` coverage.

## Planned maintained surface after S02

The maintained surface after regrouping is explicitly:

- `tests/test_install_preflight.bats`
- `tests/test_install_filesystem.bats`
- `tests/test_install_metadata_copy.bats`
- `tests/test_install_project_sync.bats`
- `tests/test_install_executable_verification.bats`
- `tests/test_install_template_render.bats`
- `tests/test_install_handoff.bats`
- `tests/test_skill_template_shape.bats`

The deferred/non-maintained documentation reference surface remains `tests/test_documentation_contract.bats` until S03 relocates it out of the maintained `tests/*.bats` entrypoint.

## Current source surface status

- `tests/test_install_preflight.bats` is already phase-local and stays maintained.
- `tests/test_install_environment.bats` is transitional: every maintained scenario below moves into `filesystem`, `project-sync`, `executable-verification`, `template-render`, or final `install` ownership, and the mixed file should disappear by T03.
- `tests/test_install_project_sync.bats` stays maintained during the split, but metadata-copy-only coverage moves out so the surviving file owns only project-sync success/failure semantics plus ordering after metadata-copy completes.
- `tests/test_skill_template_shape.bats` remains the helper-owned placeholder/runtime-value boundary and is the only maintained suite allowed to assert direct render substitution details.
- `tests/test_documentation_contract.bats` is deferred/non-maintained S03 reference work and should leave the maintained `tests/*.bats` entrypoint.

## Known documentation drift to leave for S03

- `README.md` still tells maintainers to run `PATH="$PWD/.tools/bats/bin:$PATH" bats tests/test_documentation_contract.bats tests/test_install_preflight.bats` and still lists `tests/test_install_environment.bats` as a maintained surface.
- `.gsd/REQUIREMENTS.md` still records legacy verification commands such as `bash tests/test_install_environment.sh` and `bash tests/test_install_project_sync.sh`, which no longer match the Bats-only maintained surface.
- This task records the mismatch only. Do not treat README/help wording or requirement-proof text as maintained installer-suite ownership in S02.

## Scenario ownership map

| Status | Current source file | Exact current `@test` title | Concrete boundary protected | Target owner after regrouping | Follow-on note |
| --- | --- | --- | --- | --- | --- |
| maintained | `tests/test_install_preflight.bats` | `defaults resolve in non-interactive mode and complete deterministic install` | Config/default resolution stays deterministic in non-interactive mode; completion is only the success witness. | `tests/test_install_preflight.bats` | Already phase-local; keep semantic config/install anchors instead of broader prose freezes. |
| maintained | `tests/test_install_preflight.bats` | `explicit flags override defaults and trim whitespace` | Config parsing trims and applies explicit `--skill-root`, `--skill-name`, and `--server-name` overrides before mutation. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `interactive prompt accepts bare Enter defaults` | Interactive config prompts accept default values without changing the resolved install contract. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `unknown flag fails with targeted message` | Config parsing rejects unsupported flags with a targeted next action before any install mutation. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `missing option value fails clearly` | Config parsing rejects missing option values before any filesystem mutation. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `unsupported platform blocks before mutation` | Platform preflight blocks unsupported OS values before filesystem mutation. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `empty platform probe is treated as preflight failure` | Platform probe failure aborts preflight when `uname` output is empty or unusable. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `non-interactive mode suppresses prompting` | Non-interactive config resolution stays prompt-free. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `missing uv prints guidance and declined install fails with no mutation` | `uv` preflight prints guided-install help, then fails closed before mutation when the guided path is declined. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `malformed uv probe output is treated as unavailable` | `uv` probe sanitization treats malformed output as unavailable instead of continuing with a bad tool path. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_install_preflight.bats` | `missing uv in non-interactive mode fails fast without prompt or snippet output` | `uv` preflight fails closed in non-interactive mode with no prompt and no MCP handoff snippet. | `tests/test_install_preflight.bats` | Already phase-local. |
| maintained | `tests/test_skill_template_shape.bats` | `render helper publishes the requested destination with substituted runtime values` | Helper-owned final-file publication plus literal skill/server/ddgs substitution at the render seam. | `tests/test_skill_template_shape.bats` | Keep this as the only maintained direct runtime-value assertion surface. |
| maintained | `tests/test_skill_template_shape.bats` | `render helper failures leave an existing destination untouched` | Helper-owned atomic publish/fail-closed overwrite boundary when rendering fails. | `tests/test_skill_template_shape.bats` | Keep this outside installer phase suites. |
| maintained | `tests/test_skill_template_shape.bats` | `template source exposes only the supported runtime placeholders` | Helper-owned placeholder inventory contract for `{{SKILL_NAME}}`, `{{SERVER_NAME}}`, and `{{DDGS_EXECUTABLE_PATH}}`. | `tests/test_skill_template_shape.bats` | Keep this as the only maintained direct placeholder-shape check. |
| maintained | `tests/test_install_environment.bats` | `fresh install emits handoff snippet and removes render staging helpers` | Final `install` handoff/completion success ordering after a successful render; staged-helper cleanup is a supporting success observation. | `tests/test_install_handoff.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `existing target directory conflict fails before mutation and suppresses handoff` | `filesystem` conflict blocks mutation and suppresses downstream handoff/completion. | `tests/test_install_filesystem.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `project-sync non-zero exits with phase diagnostics and no completion output` | `project-sync` failure halts before `template-render` and suppresses handoff/completion. | `tests/test_install_project_sync.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `missing ddgs executable fails verification and suppresses handoff` | `executable-verification` fails closed when canonical `.venv/bin/ddgs` is missing. | `tests/test_install_executable_verification.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `non-executable ddgs path fails verification and suppresses handoff` | `executable-verification` fails closed when canonical `.venv/bin/ddgs` exists but is not executable. | `tests/test_install_executable_verification.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `missing template fails in template-render phase without partial SKILL.md` | `template-render` fails closed when the source template is missing and no partial final `SKILL.md` may remain. | `tests/test_install_template_render.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `unreadable template fails in template-render phase without partial SKILL.md` | `template-render` fails closed when the source template is unreadable and no partial final `SKILL.md` may remain. | `tests/test_install_template_render.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `render helper runtime failure preserves staged diagnostics and suppresses completion` | `template-render` runtime failure retains `.template-render-stage`, leaves no final `SKILL.md`, and suppresses handoff/completion. | `tests/test_install_template_render.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_environment.bats` | `unusual server names are JSON-escaped in handoff snippet` | Final `install` handoff JSON-escapes the selected server label while preserving literal rendered values and the canonical command path. | `tests/test_install_handoff.bats` | Move out of the transitional environment bucket. |
| maintained | `tests/test_install_project_sync.bats` | `metadata-copy runs before sync and preserves canonical ddgs handoff path` | `project-sync` success ordering after `metadata-copy` completes, including canonical ddgs-path continuity into the final handoff. | `tests/test_install_project_sync.bats` | Keep as the sync-success/ordering owner after metadata-copy-only cases move out. |
| maintained | `tests/test_install_project_sync.bats` | `absent source uv.lock is logged and target uv.lock is retained after sync` | Optional lockfile absence is logged during `metadata-copy`, while `project-sync` still retains the target `uv.lock` after provisioning. | `tests/test_install_project_sync.bats` | Keep with sync-retention semantics rather than pure copy-only coverage. |
| maintained | `tests/test_install_project_sync.bats` | `present source uv.lock is copied into target metadata` | `metadata-copy` copies the optional lockfile into the target when the source lock exists. | `tests/test_install_metadata_copy.bats` | Move out of `tests/test_install_project_sync.bats` during T02. |
| maintained | `tests/test_install_project_sync.bats` | `project-sync failure keeps copied metadata but suppresses handoff and completion output` | `project-sync` failure retains copied diagnostics files but suppresses executable verification, render, handoff, and completion. | `tests/test_install_project_sync.bats` | Keep as the main sync failure-path owner. |
| maintained | `tests/test_install_project_sync.bats` | `malformed sync layout fails canonical executable verification and suppresses handoff` | `executable-verification` catches a misplaced ddgs path after sync and suppresses the MCP handoff. | `tests/test_install_executable_verification.bats` | Move into the executable-verification suite during T03. |
| maintained | `tests/test_install_project_sync.bats` | `missing source pyproject.toml fails in metadata-copy before project-sync` | `metadata-copy` fails closed when the required manifest is missing. | `tests/test_install_metadata_copy.bats` | Move out of `tests/test_install_project_sync.bats` during T02. |
| maintained | `tests/test_install_project_sync.bats` | `unreadable source pyproject.toml fails in metadata-copy before provisioning` | `metadata-copy` fails closed when the required manifest exists but is unreadable. | `tests/test_install_metadata_copy.bats` | Move out of `tests/test_install_project_sync.bats` during T02. |
| maintained | `tests/test_install_project_sync.bats` | `unreadable source uv.lock fails in metadata-copy before project-sync` | `metadata-copy` fails closed when the optional lockfile exists but is unreadable. | `tests/test_install_metadata_copy.bats` | Move out of `tests/test_install_project_sync.bats` during T02. |
| maintained | `tests/test_install_project_sync.bats` | `unusual but valid target paths with spaces still receive copied metadata` | `metadata-copy` handles valid target paths with spaces without weakening copied-file guarantees. | `tests/test_install_metadata_copy.bats` | Move out of `tests/test_install_project_sync.bats` during T02. |
| deferred | `tests/test_documentation_contract.bats` | `README describes the shipped writing-skills-first contract` | README wording/section-shape verification only; this is not a maintained installer phase boundary. | `tests/test_documentation_contract.bats` | Keep only as deferred S03 reference work outside the maintained `tests/*.bats` surface. |
| deferred | `tests/test_documentation_contract.bats` | `install help repeats the single-file skill contract` | `install.sh --help` wording/section-shape verification only; this is not a maintained installer phase boundary. | `tests/test_documentation_contract.bats` | Keep only as deferred S03 reference work outside the maintained `tests/*.bats` surface. |

## Owner summary

| Target owner after regrouping | Scenario count | Status |
| --- | ---: | --- |
| `tests/test_install_preflight.bats` | 11 | maintained |
| `tests/test_install_filesystem.bats` | 1 | maintained |
| `tests/test_install_metadata_copy.bats` | 5 | maintained |
| `tests/test_install_project_sync.bats` | 4 | maintained |
| `tests/test_install_executable_verification.bats` | 3 | maintained |
| `tests/test_install_template_render.bats` | 3 | maintained |
| `tests/test_install_handoff.bats` | 2 | maintained |
| `tests/test_skill_template_shape.bats` | 3 | maintained |
| `tests/test_documentation_contract.bats` | 2 | deferred |

Map completeness target: 32 maintained scenarios + 2 deferred documentation scenarios = 34 total rows, with every current title listed exactly once.
