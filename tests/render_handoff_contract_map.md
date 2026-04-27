# Render and handoff contract map

This file is S01's per-scenario source of truth for the render/handoff cleanup in M006-nxnvwf.
It inventories every render-heavy `@test` from:

- `tests/test_skill_template_shape.bats`
- `tests/test_install_environment.bats`
- `tests/test_install_project_sync.bats`
- `tests/test_documentation_contract.bats`

It follows D033, D035, and D036:

- keep installer-contract assertions that protect real render/handoff boundaries;
- remove section-shape and prose-wording policing from the maintained Bats surface; and
- defer README/help wording alignment to S03 instead of treating wording churn as an installer regression.

## Inclusion rule

A scenario belongs in this map when its current assertions reach any of these boundaries:

1. final `SKILL.md` publication or the absence of a partial final artifact;
2. placeholder replacement or runtime-value injection (`skill`, `server`, canonical `.venv/bin/ddgs` path);
3. `template-render` phase ordering, cleanup, or staged-helper retention;
4. final MCP handoff/completion emission or suppression; or
5. JSON escaping of user-provided server labels in the handoff snippet.

Documentation-only wording checks are still listed here because they are part of the current cleanup target, but they are **not** kept as maintained render coverage.

## Duplicate-title check

- Included render-heavy titles are unique; no duplicate `@test` names were found across the four source suites.
- Included set: **16** render-heavy/documentation-contract scenarios.
- Explicitly excluded appendix set: **6** non-render-only project-sync scenarios from the same source files, listed so future cleanup does not silently widen this map.

## Per-scenario keep/remove/defer map

| Source file | Exact current `@test` title | S01 disposition | Boundary protected or reason | Owner after cleanup | Requirement trace | Follow-on note |
| --- | --- | --- | --- | --- | --- | --- |
| `tests/test_skill_template_shape.bats` | `@test "rendered skill keeps the writing-skills-first shape and placeholder contract"` | keep | Helper success-path contract: publish the requested destination file, inject the selected skill/server/ddgs values, and remove required placeholders from the final artifact. Remove section-order, section-count, and prose-wording checks from this scenario. | helper contract | R058, R059 | Current title overstates the kept scope; T02 may retitle it, but preserve lineage from this exact title. |
| `tests/test_skill_template_shape.bats` | `@test "template source keeps only the supported section set and runtime placeholders"` | keep | Helper source-template contract: keep the exact supported runtime placeholder inventory (`{{SKILL_NAME}}`, `{{SERVER_NAME}}`, `{{DDGS_EXECUTABLE_PATH}}`). Remove section-set policing from the maintained surface. | helper contract | R058, R059 | T02 should keep the placeholder inventory and drop heading/shape assertions; if renamed, keep this original title in summary notes. |
| `tests/test_install_environment.bats` | `@test "fresh install emits handoff snippet and removes render staging helpers"` | keep | Installer success boundary: successful render publishes final `SKILL.md`, removes `.template-render-stage`, injects the canonical `.venv/bin/ddgs` path, emits exactly one handoff block after render, and then emits completion. Remove generated-section and prose-wording assertions from this scenario. | installer integration contract | R058, R059, R060 | S02 should group this under `template-render`/`install` success ordering rather than document shape. |
| `tests/test_install_environment.bats` | `@test "existing target directory conflict fails before mutation and suppresses handoff"` | keep | Fail-closed filesystem boundary: a pre-mutation target conflict must stop before render/handoff and suppress both final handoff and completion output. | installer integration contract | R058, R059, R060 | S02 should likely move this into the filesystem phase suite while preserving handoff suppression. |
| `tests/test_install_environment.bats` | `@test "project-sync non-zero exits with phase diagnostics and no completion output"` | keep | Fail-closed project-sync boundary: a non-zero sync exit must stop before `template-render`, keep phase-prefixed diagnostics, and suppress handoff/completion. | installer integration contract | R058, R059, R060 | This belongs with project-sync phase coverage in S02, not a document-shape bucket. |
| `tests/test_install_environment.bats` | `@test "missing ddgs executable fails verification and suppresses handoff"` | keep | Executable-verification boundary: missing canonical `.venv/bin/ddgs` must fail before render/handoff and suppress final success signals. | installer integration contract | R058, R059, R060 | Keep the semantic executable-verification anchor; no wording freeze needed. |
| `tests/test_install_environment.bats` | `@test "non-executable ddgs path fails verification and suppresses handoff"` | keep | Executable-verification boundary: a non-executable canonical ddgs path must fail closed before render/handoff. | installer integration contract | R058, R059, R060 | Keep as the non-executable variant of the same canonical-path contract. |
| `tests/test_install_environment.bats` | `@test "missing template fails in template-render phase without partial SKILL.md"` | keep | `template-render` failure boundary: missing template must surface a phase-prefixed error, publish no final `SKILL.md`, and suppress handoff/completion. | installer integration contract | R058, R059, R060 | Keep the no-partial-artifact guarantee; avoid exact NEXT/help wording policing. |
| `tests/test_install_environment.bats` | `@test "unreadable template fails in template-render phase without partial SKILL.md"` | keep | `template-render` failure boundary: unreadable template must fail before final publication and suppress handoff/completion. | installer integration contract | R058, R059, R060 | Same kept boundary as missing-template, but for unreadable input. |
| `tests/test_install_environment.bats` | `@test "render helper runtime failure preserves staged diagnostics and suppresses completion"` | keep | Runtime render-failure boundary: helper stderr/exit must stay visible, `.template-render-stage` must be retained for diagnostics, no final `SKILL.md` may remain, and handoff/completion stay suppressed. | installer integration contract | R058, R059, R060 | This is the retained stage-cleanup-vs-retention contract for S02. |
| `tests/test_install_environment.bats` | `@test "unusual server names are JSON-escaped in handoff snippet"` | keep | Render/handoff boundary: literal server value must survive into rendered `SKILL.md`, while the MCP handoff block must JSON-escape that same value and keep the canonical ddgs command path. | installer integration contract | R058, R059, R060 | Keep escaping and canonical-path checks; remove remaining wording assertions from the rendered artifact. |
| `tests/test_install_project_sync.bats` | `@test "metadata-copy runs before sync and preserves canonical ddgs handoff path"` | keep | Multi-phase success ordering boundary: metadata copy must complete before sync, sync must complete before executable verification, render must complete before handoff, and both final `SKILL.md` and the handoff block must use the canonical `.venv/bin/ddgs` path. | installer integration contract | R058, R059, R060 | This is the clearest ordering anchor for S02's phase-based split. |
| `tests/test_install_project_sync.bats` | `@test "project-sync failure keeps copied metadata but suppresses handoff and completion output"` | keep | Project-sync failure boundary: copied metadata stays for diagnostics, but executable verification/render/handoff/completion must not run after a sync failure. | installer integration contract | R058, R059, R060 | Keep as failure-path coverage for the project-sync phase. |
| `tests/test_install_project_sync.bats` | `@test "malformed sync layout fails canonical executable verification and suppresses handoff"` | keep | Canonical-path boundary: a misplaced executable must fail the `.venv/bin/ddgs` contract and suppress the MCP handoff block. | installer integration contract | R058, R059, R060 | Keep as the malformed-layout counterpart to the canonical ddgs path invariant. |
| `tests/test_documentation_contract.bats` | `@test "README describes the shipped writing-skills-first contract"` | defer | Documentation-only wording/shape assertions about README copy are outside the maintained installer/render contract. Remove from the maintained Bats surface now and revisit in S03 documentation alignment if a doc-validation surface is still needed. | S03 documentation alignment | R058, R059 | Do **not** count this as kept render coverage. |
| `tests/test_documentation_contract.bats` | `@test "install help repeats the single-file skill contract"` | defer | Documentation/help wording assertions are outside the maintained installer/render contract. Keep only semantic CLI anchors elsewhere if needed; do not keep exact section-shape/help-copy policing in the main Bats surface. | S03 documentation alignment | R058, R059 | Do **not** count this as kept render coverage. |

## Appendix: source-file titles explicitly outside the render/handoff inventory

These scenarios are adjacent because they live in the same source suites, but they are **not render-heavy** under the inclusion rule above. They should stay traceable during S02 phase reorganization, but this file does not use them to justify render/handoff retention.

| Source file | Exact current `@test` title | Why it is outside this map |
| --- | --- | --- |
| `tests/test_install_project_sync.bats` | `@test "absent source uv.lock is logged and target uv.lock is retained after sync"` | Lockfile-presence and metadata-retention coverage; no render publication, placeholder substitution, stage cleanup/retention, or handoff-ordering assertion. |
| `tests/test_install_project_sync.bats` | `@test "present source uv.lock is copied into target metadata"` | Optional lockfile copy boundary only; not a render/handoff scenario. |
| `tests/test_install_project_sync.bats` | `@test "missing source pyproject.toml fails in metadata-copy before project-sync"` | Required metadata-copy failure boundary only; not a render-heavy scenario. |
| `tests/test_install_project_sync.bats` | `@test "unreadable source pyproject.toml fails in metadata-copy before provisioning"` | Required metadata readability boundary only; not a render-heavy scenario. |
| `tests/test_install_project_sync.bats` | `@test "unreadable source uv.lock fails in metadata-copy before project-sync"` | Optional lockfile readability boundary only; not a render-heavy scenario. |
| `tests/test_install_project_sync.bats` | `@test "unusual but valid target paths with spaces still receive copied metadata"` | Path-quoting/metadata-copy coverage only; it does not reach the render/handoff contract. |

## Summary for downstream work

- **Helper-owned keep set for T02:** direct destination publication, selected runtime-value injection, and runtime-placeholder inventory.
- **Installer-integration keep set for T03/S02:** phase ordering, canonical `.venv/bin/ddgs` injection, stage cleanup vs retention, JSON-escaped handoff output, and fail-closed handoff/completion suppression.
- **Documentation-only set for S03:** README/help wording and generated section-shape alignment; these are deferred out of the maintained Bats contract surface.
