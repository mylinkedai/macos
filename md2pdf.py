#!/usr/bin/env python3
"""Convert Markdown to a same-directory PDF using Pandoc and headless Chrome."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


CSS = r"""
@page { size: Letter; margin: 0.65in 0.7in 0.7in; @bottom-center { content: counter(page); color: #666; font-size: 9pt; } }
html { font-family: "Hiragino Sans GB", "PingFang SC", sans-serif; color: #1f2937; font-size: 10.5pt; line-height: 1.45; }
body { margin: 0; }
h1, h2, h3, h4 { color: #17365d; line-height: 1.2; break-after: avoid; }
h1 { font-size: 21pt; margin: 1.1em 0 0.45em; border-bottom: 2px solid #7699c4; padding-bottom: 0.15em; }
h2 { font-size: 15pt; margin: 1em 0 0.35em; }
h3 { font-size: 12pt; margin: 0.9em 0 0.25em; }
p, ul, ol, blockquote { margin: 0.35em 0 0.65em; }
li { margin: 0.15em 0; }
blockquote { border-left: 4px solid #9ab6d8; background: #f3f7fb; padding: 0.45em 0.75em; }
table { border-collapse: collapse; width: 100%; margin: 0.55em 0 0.9em; font-size: 9pt; break-inside: avoid; }
th, td { border: 0.7px solid #9ca3af; padding: 0.35em 0.45em; vertical-align: top; }
th { background: #dce8f5; color: #17365d; text-align: left; }
tr:nth-child(even) td { background: #f8fafc; }
code { font-family: Menlo, monospace; font-size: 0.9em; }
a { color: #225ea8; text-decoration: none; }
#TOC { background: #f6f8fb; border: 1px solid #cbd5e1; padding: 0.7em 1em; margin-bottom: 1.2em; }
#TOC ul { margin: 0.2em 0; padding-left: 1.4em; }
"""


def executable(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"Required program not found: {name}")
    return path


def chrome_executable() -> str:
    candidates = [
        shutil.which("google-chrome"),
        shutil.which("chromium"),
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise RuntimeError("Required program not found: Google Chrome or Chromium")


def convert(source: Path, output: Path | None = None) -> Path:
    source = source.expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(f"Markdown file not found: {source}")
    if source.suffix.lower() not in {".md", ".markdown"}:
        raise ValueError(f"Expected a Markdown file, got: {source.name}")

    destination = (output.expanduser().resolve() if output else source.with_suffix(".pdf"))
    destination.parent.mkdir(parents=True, exist_ok=True)

    command = [
        executable("pandoc"),
        str(source),
        "--from=gfm+smart",
        "--standalone",
        "--resource-path",
        str(source.parent),
        "--metadata",
        f"title={source.stem.replace('_', ' ')}",
        "--toc",
        "--toc-depth=2",
        "--number-sections",
    ]
    html = subprocess.run(
        command, check=True, cwd=source.parent, capture_output=True
    ).stdout.decode("utf-8")
    html = html.replace("</head>", f"<style>{CSS}</style></head>", 1)
    with tempfile.NamedTemporaryFile(mode="w", suffix=".html", encoding="utf-8") as page:
        page.write(html)
        page.flush()
        subprocess.run(
            [
                chrome_executable(),
                "--headless",
                "--disable-gpu",
                "--no-pdf-header-footer",
                f"--print-to-pdf={destination}",
                Path(page.name).as_uri(),
            ],
            check=True,
            cwd=source.parent,
        )
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert a Markdown file to PDF beside the source file."
    )
    parser.add_argument("markdown", type=Path, help="Markdown file to convert")
    parser.add_argument("-o", "--output", type=Path, help="Optional output PDF path")
    args = parser.parse_args()

    try:
        result = convert(args.markdown, args.output)
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"md2pdf: {error}", file=sys.stderr)
        return 1

    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
