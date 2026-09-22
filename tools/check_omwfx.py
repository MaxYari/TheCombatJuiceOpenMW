#!/usr/bin/env python3
"""Checks an .omwfx shader against OpenMW's own parser rules, without the game.

    python3 tools/check_omwfx.py shaders/*.omwfx

The rules come from components/fx/lexer.cpp and components/fx/technique.cpp:

- The lexer only skips comments inside the bodies of `fragment`, `vertex` and
  `compute` blocks, which it consumes whole (Lexer::jump). Anywhere else a '/'
  is an unexpected token and the whole shader fails to load - which, when a mod
  loads the shader from Lua, takes the mod's script down with it.
- Every block key is checked against a fixed list; an unknown one is an error.
- `passes` is comma separated, and every name in it must be a declared pass.

Exit status is non-zero if anything looks wrong.
"""

import re
import sys
from pathlib import Path

GLSL_BLOCKS = {"fragment", "vertex", "compute"}

BLOCK_KEYS = {
    "technique": {"passes", "version", "description", "author", "glsl_version", "flags", "hdr",
                  "pass_normals", "pass_lights", "glsl_profile", "glsl_extensions", "dynamic"},
    "render_target": {"min_filter", "mag_filter", "wrap_s", "wrap_t", "width_ratio", "height_ratio",
                      "width", "height", "internal_format", "source_type", "source_format",
                      "mipmaps", "clear_color"},
    "uniform": {"default", "size", "min", "max", "step", "static", "description", "header",
                "display_name", "widget_type"},
    "sampler": {"source", "min_filter", "mag_filter", "wrap_s", "wrap_t", "wrap_r", "compression",
                "source_format", "source_type", "internal_format"},
}

KEYWORDS = ("shared", "technique", "render_target", "vertex", "fragment", "compute",
            "sampler_1d", "sampler_2d", "sampler_3d", "uniform_bool", "uniform_float",
            "uniform_int", "uniform_vec2", "uniform_vec3", "uniform_vec4")

BLOCK_RE = re.compile(r"^\s*(" + "|".join(KEYWORDS) + r")\b\s*([A-Za-z_][A-Za-z0-9_]*)?\s*(\([^)]*\))?\s*\{")


def kind_of(keyword):
    if keyword in GLSL_BLOCKS:
        return "glsl"
    if keyword.startswith("uniform_"):
        return "uniform"
    if keyword.startswith("sampler_"):
        return "sampler"
    return keyword


def check(path):
    text = path.read_text()
    problems = []
    lines = text.splitlines()

    i = 0
    passes_declared = set()
    passes_listed = []
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        match = BLOCK_RE.match(line)
        if not match:
            if "//" in line or "/*" in line:
                problems.append(f"{path}:{i + 1}: comment outside a GLSL block - the lexer has no "
                                f"comment handling there, this fails with \"unexpected token </>\"")
            elif stripped not in ("}", "{"):
                problems.append(f"{path}:{i + 1}: not a block declaration and not inside one: {stripped!r}")
            i += 1
            continue

        keyword, name, _header = match.groups()
        kind = kind_of(keyword)
        if keyword in GLSL_BLOCKS and name:
            passes_declared.add(name)

        # Walk to the matching close bracket.
        depth = line.count("{") - line.count("}")
        body_start = i + 1
        j = i
        while depth > 0 and j + 1 < len(lines):
            j += 1
            depth += lines[j].count("{") - lines[j].count("}")
        body = lines[body_start:j]

        if kind == "glsl":
            pass  # comments and arbitrary GLSL are fine in here
        else:
            allowed = BLOCK_KEYS.get(kind)
            for offset, body_line in enumerate(body):
                entry = body_line.strip()
                if not entry:
                    continue
                if "//" in entry or "/*" in entry:
                    problems.append(f"{path}:{body_start + offset + 1}: comment inside a "
                                    f"'{keyword}' block, which is parsed token by token")
                    continue
                key = entry.split("=", 1)[0].strip()
                if allowed is not None and key and key not in allowed:
                    problems.append(f"{path}:{body_start + offset + 1}: '{keyword}' block has no "
                                    f"key '{key}' (known: {', '.join(sorted(allowed))})")
                if entry and not entry.endswith(";") and not entry.endswith("{") and "}" not in entry:
                    problems.append(f"{path}:{body_start + offset + 1}: missing ';' after {entry!r}")
                if kind == "technique" and key == "passes":
                    value = entry.split("=", 1)[1].rstrip(";").strip()
                    passes_listed = [p.strip() for p in value.split(",")]
        i = j + 1

    if not passes_listed:
        problems.append(f"{path}: the technique block declares no passes")
    for name in passes_listed:
        if name not in passes_declared:
            problems.append(f"{path}: pass '{name}' is listed in the technique block but no "
                            f"fragment/vertex/compute block declares it")

    return problems


def main():
    paths = [Path(p) for p in sys.argv[1:]] or sorted(Path("shaders").glob("*.omwfx"))
    failed = False
    for path in paths:
        problems = check(path)
        if problems:
            failed = True
            for p in problems:
                print(p)
        else:
            print(f"{path}: ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
