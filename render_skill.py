#!/usr/bin/env python3
"""Render SKILL.md from a Jinja template and publish it atomically."""

from __future__ import annotations

import argparse
import contextlib
import os
import sys
import tempfile
from pathlib import Path

from jinja2 import Environment, StrictUndefined, TemplateError

_REQUIRED_PLACEHOLDERS = (
    "{{SKILL_NAME}}",
    "{{SERVER_NAME}}",
    "{{DDGS_EXECUTABLE_PATH}}",
)


class RenderFailure(RuntimeError):
    """Raised when template rendering or publication fails."""


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render SKILL.md from SKILL.md.jinja using strict Jinja semantics.",
    )
    parser.add_argument("--template", required=True, help="Path to SKILL.md.jinja")
    parser.add_argument("--destination", required=True, help="Path to publish SKILL.md")
    parser.add_argument("--skill-name", required=True, dest="skill_name")
    parser.add_argument("--server-name", required=True, dest="server_name")
    parser.add_argument(
        "--ddgs-executable-path",
        required=True,
        dest="ddgs_executable_path",
        help="Resolved path to the installed ddgs executable",
    )
    return parser


def _read_template(template_path: Path) -> str:
    if not template_path.exists():
        raise RenderFailure(f"Template not found: {template_path}")

    if not template_path.is_file():
        raise RenderFailure(f"Template path is not a regular file: {template_path}")

    if not os.access(template_path, os.R_OK):
        raise RenderFailure(f"Template file is not readable: {template_path}")

    try:
        template_source = template_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise RenderFailure(f"Failed to read template: {template_path}") from exc

    if template_source == "":
        raise RenderFailure(f"Template content is empty: {template_path}")

    return template_source


def _render_template(template_source: str, context: dict[str, str]) -> str:
    environment = Environment(
        autoescape=False,
        keep_trailing_newline=True,
        undefined=StrictUndefined,
    )

    try:
        rendered = environment.from_string(template_source).render(**context)
    except TemplateError as exc:
        raise RenderFailure(f"Failed to render template with Jinja2: {exc}") from exc

    if rendered == "":
        raise RenderFailure("Rendered SKILL.md content is empty after substitution.")

    unresolved = [placeholder for placeholder in _REQUIRED_PLACEHOLDERS if placeholder in rendered]
    if unresolved:
        raise RenderFailure(
            "Template placeholder substitution failed for one or more required variables. "
            "Ensure SKILL.md.jinja uses {{SKILL_NAME}}, {{SERVER_NAME}}, and {{DDGS_EXECUTABLE_PATH}} exactly."
        )

    if not rendered.endswith("\n"):
        rendered = f"{rendered}\n"

    return rendered


def _publish_atomically(destination_path: Path, content: str) -> None:
    parent = destination_path.parent

    if str(parent) == "":
        raise RenderFailure("Destination path has no parent directory.")

    if not parent.exists():
        raise RenderFailure(f"Destination directory does not exist: {parent}")

    if not parent.is_dir():
        raise RenderFailure(f"Destination parent is not a directory: {parent}")

    try:
        temp_fd, temp_file = tempfile.mkstemp(
            prefix=f".{destination_path.name}.tmp.",
            dir=str(parent),
        )
    except OSError as exc:
        raise RenderFailure(
            f"Failed to create temporary render file under {parent}."
        ) from exc

    temp_path = Path(temp_file)
    try:
        with os.fdopen(temp_fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)

        os.replace(temp_path, destination_path)
    except OSError as exc:
        with contextlib.suppress(FileNotFoundError):
            temp_path.unlink()
        raise RenderFailure(
            f"Failed to publish rendered SKILL.md to {destination_path}."
        ) from exc

    if not destination_path.is_file():
        raise RenderFailure(
            f"Render completed but destination file is missing: {destination_path}"
        )


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    template_path = Path(args.template)
    destination_path = Path(args.destination)

    context = {
        "SKILL_NAME": args.skill_name,
        "SERVER_NAME": args.server_name,
        "DDGS_EXECUTABLE_PATH": args.ddgs_executable_path,
    }

    try:
        template_source = _read_template(template_path)
        rendered = _render_template(template_source, context)
        _publish_atomically(destination_path, rendered)
    except RenderFailure as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print(str(destination_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
