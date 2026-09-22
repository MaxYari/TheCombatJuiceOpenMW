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

If glslangValidator is installed, each pass is also compiled as GLSL 120 with
the declarations OpenMW puts in front of it, which catches ordinary shader
mistakes. Pass --no-glsl to skip that.

Exit status is non-zero if anything looks wrong.
"""

import re
import subprocess
import sys
import tempfile
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


GLSL_TYPES = {"float": "float", "int": "int", "bool": "bool",
              "vec2": "vec2", "vec3": "vec3", "vec4": "vec4"}

# What the engine's preprocessor puts in front of every pass, cut down to what
# is needed to type check one.
GLSL_PRELUDE = """#version 120
#define omw_In varying
#define omw_Out varying
#define omw_Texture1D texture1D
#define omw_Texture2D texture2D
#define omw_Texture3D texture3D
#define omw_Vertex gl_Vertex
#define omw_Position gl_Position
vec4 omw_FragColor;
struct OmwGlobals {
    vec2 resolution; vec2 rcpResolution; float simulationTime; float deltaSimulationTime;
    float near; float far; float fov; float gameHour; float waterHeight; float windSpeed;
    float weatherTransition; int weatherID; int nextWeatherID; int frameNumber;
    bool isUnderwater; bool isInterior; bool isWaterEnabled;
};
uniform OmwGlobals omw;
vec4 omw_GetLastShader(vec2 uv);
vec4 omw_GetLastPass(vec2 uv);
float omw_GetDepth(vec2 uv);
vec3 omw_GetNormals(vec2 uv);
float omw_GetEyeAdaptation();
"""


def compile_passes(path):
    """Compile every GLSL block with glslangValidator, if it is installed."""
    text = path.read_text()
    uniforms = [f"uniform {GLSL_TYPES[kind]} {name};"
                for kind, name in re.findall(r"^uniform_(\w+)\s+(\w+)\s*\{", text, re.M)
                if kind in GLSL_TYPES]
    uniforms += [f"uniform sampler2D {name};"
                 for name in re.findall(r"^render_target\s+(\w+)\s*\{", text, re.M)]
    uniforms += [f"uniform sampler2D {name};"
                 for name in re.findall(r"^sampler_2d\s+(\w+)\s*\{", text, re.M)]

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        for kind, name, body in re.findall(
                r"^(fragment|vertex)\s+(\w+)\s*(?:\([^)]*\))?\s*\{\n(.*?)\n\}\s*$",
                text, re.M | re.S):
            stage = "frag" if kind == "fragment" else "vert"
            source = Path(tmp) / f"{name}.{stage}"
            source.write_text(GLSL_PRELUDE + "\n".join(uniforms) + "\n" + body + "\n")
            result = subprocess.run(["glslangValidator", "-S", stage, str(source)],
                                    capture_output=True, text=True)
            if result.returncode != 0:
                output = (result.stdout + result.stderr).strip()
                problems.append(f"{path}: pass '{name}' does not compile:\n{output}")
    return problems


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
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    with_glsl = "--no-glsl" not in sys.argv[1:]
    paths = [Path(p) for p in args] or sorted(Path("shaders").glob("*.omwfx"))

    if with_glsl:
        try:
            subprocess.run(["glslangValidator", "--version"], capture_output=True)
        except FileNotFoundError:
            print("note: glslangValidator is not installed, only the block structure is checked")
            with_glsl = False

    failed = False
    for path in paths:
        problems = check(path)
        if with_glsl and not problems:
            problems += compile_passes(path)
        if problems:
            failed = True
            for p in problems:
                print(p)
        else:
            print(f"{path}: ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
