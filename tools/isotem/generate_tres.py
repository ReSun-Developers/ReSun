"""Generate four-direction TerrainObject .tres variants from the TS isotem catalog.

Reads `tools/isotem/isotem_catalog.json` (produced by catalog.py, canonical
orientation) and writes one `TerrainObject` resource per directional variant —
every base family × 4 rotations (`<base>_n`, `<base>_e`, `<base>_s`,
`<base>_w`) — to `games/ts/terrain_objects/`.

Each cell carries baked geometry: `corners` (4 absolute vertex heights in
NW/NE/SE/SW order, rotated to the variant's facing), a `crease` triangulation
diagonal derived from the corner pattern, `land`, and optional `slope` (TS
RampType provenance). Shared art is rotated by the variant's directional
suffix, so one GLB submesh per family serves all four variants.

Usage:
    python tools/isotem/generate_tres.py [--catalog PATH] [--out DIR]
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

# .tem surface id -> game LandType id
LAND_MAP = {
    15: "rock",
    13: "clear",
    14: "clear",
}

KIND_TO_CELL_TYPE = {
    "cliff": "cliff",
    "wcliff": "cliff",
    "dcliff": "cliff",
    "ramp": "ramp",
    "clat": "slope",
    "slope": "slope",
    "clear": "clear",
}

DEFAULT_CATALOG = "tools/isotem/isotem_catalog.json"
DEFAULT_OUT = "games/ts/terrain_objects"

TERRAIN_OBJECT_SCRIPT = "res://scripts/data/TerrainObject.gd"

# Directional variant suffixes in renderer order (n/e/s/w), mapped to the
# footprint rotation transform: n=0, e=90CW, s=180, w=270CW.
DIRECTIONS = ["n", "e", "s", "w"]

# A full cliff tier is 4 lattice steps; cells at or above this on a tile edge
# are the high side, below it the low side.
CLIFF_STEP = 4

# WAE/FinalSun RampCornerHeights: per RampType, corner offsets from the cell's
# level in NW, NE, SE, SW order. Type 0 = flat cell.
RAMP_CORNER_HEIGHTS = {
    0: [0, 0, 0, 0], 1: [0, 1, 1, 0], 2: [0, 0, 1, 1], 3: [1, 0, 0, 1],
    4: [1, 1, 0, 0], 5: [0, 0, 1, 0], 6: [0, 0, 0, 1], 7: [1, 0, 0, 0],
    8: [0, 1, 0, 0], 9: [0, 1, 1, 1], 10: [1, 0, 1, 1], 11: [1, 1, 0, 1],
    12: [1, 1, 1, 0], 13: [0, 1, 2, 1], 14: [1, 0, 1, 2], 15: [2, 1, 0, 1],
    16: [1, 2, 1, 0], 17: [0, 1, 0, 1], 18: [1, 0, 1, 0], 19: [0, 1, 0, 1],
    20: [1, 0, 1, 0],
}

# Catalog ids that may dock on a ramp-role edge.
RAMP_IDS = ["ramp01", "ramp06", "ramp07", "clat01"]

NEIGHBOR_OFFSETS = {
    "north": (0, -1),
    "south": (0, 1),
    "west": (-1, 0),
    "east": (1, 0),
}

EDGE_CELLS = {
    "north": lambda w, h: [(x, 0) for x in range(w)],
    "south": lambda w, h: [(x, h - 1) for x in range(w)],
    "west": lambda w, h: [(0, y) for y in range(h)],
    "east": lambda w, h: [(w - 1, y) for y in range(h)],
}


def rotate_cell(x: int, y: int, width: int, height: int, t: int) -> tuple[int, int]:
    """Rotate a cell coordinate on a width x height grid by transform t
    (0 = identity, 1 = 90 deg CW, 2 = 180 deg, 3 = 90 deg CCW)."""
    if t == 0:
        return x, y
    if t == 1:
        return height - 1 - y, x
    if t == 2:
        return width - 1 - x, height - 1 - y
    return y, width - 1 - x


def rotate_corners(corners: list, t: int) -> list:
    """Rotate a (NW, NE, SE, SW) corner tuple by transform t (90-deg cycles)."""
    if t == 0:
        return list(corners)
    if t == 1:
        return [corners[3], corners[0], corners[1], corners[2]]
    if t == 2:
        return [corners[2], corners[3], corners[0], corners[1]]
    return [corners[1], corners[2], corners[3], corners[0]]


def derive_crease(corners: list) -> str:
    """Triangulation diagonal from the corner pattern.

    - All corners equal -> "flat" (single quad).
    - Two adjacent high corners -> planar quad -> "flat".
    - Two opposite high corners (saddle) -> split along the high diagonal -> "y".
    - One or three corners high (tent / inverted tent) -> "x".
    """
    lo: int = min(corners)
    hi: int = max(corners)
    if hi == lo:
        return "flat"
    high = [i for i, c in enumerate(corners) if c == hi]
    if len(high) == 2:
        i1, i2 = high
        if (i1 - i2) % 2 == 0:
            return "y"  # opposite corners raised
        return "flat"  # adjacent corners raised
    return "x"


def _edge_role(cells: list, width: int, height: int, kind: str, edge: str) -> str:
    """Role for a whole tile edge from the heights of the cells touching it."""
    cell_map = {(x, y): (h, land) for x, y, h, land, slope in cells}
    coords = EDGE_CELLS[edge](width, height)
    heights = [cell_map[c][0] for c in coords if c in cell_map]
    if not heights:
        return "ground"
    has_high = any(h >= CLIFF_STEP for h in heights)
    has_low = any(h < CLIFF_STEP for h in heights)
    if kind == "wcliff":
        return "water" if not has_high else "cliff"
    if has_high and has_low:
        return "cliff"
    return "ground"


def derive_cell_connections(cells: list, width: int, height: int, kind: str) -> dict:
    """Per-cell edge-role connections derived from the tile footprint.

    Each occupied cell declares its edges as `{edge: {role, allowed?}}`:
      - an edge to an in-tile neighbor at least one step lower is a drop face
        (`role = "ramp"`, `allowed` = catalog ramp ids);
      - an edge on the tile boundary takes the tile-edge role
        (`cliff`/`ground`/`water`).
    Interior edges to equal/higher neighbors carry no connection.
    """
    cell_map = {(x, y): (h, land) for x, y, h, land, slope in cells}
    edge_roles = {e: _edge_role(cells, width, height, kind, e) for e in EDGE_CELLS}
    result: dict[str, dict] = {}
    for (x, y, h, land, slope) in cells:
        conn: dict[str, dict] = {}
        for edge, (dx, dy) in NEIGHBOR_OFFSETS.items():
            nx, ny = x + dx, y + dy
            if (nx, ny) in cell_map:
                if h > cell_map[(nx, ny)][0]:
                    conn[edge] = {"role": "ramp", "allowed": RAMP_IDS}
            else:
                conn[edge] = {"role": edge_roles[edge]}
        if conn:
            result[f"{x},{y}"] = conn
    return result


def indent_dict(value: dict, indent: int) -> str:
    """Render a nested dict literal using Godot tres syntax (flat, quoted strings)."""

    def render(d: dict) -> str:
        lines = []
        for key in sorted(d):
            v = d[key]
            if isinstance(v, dict):
                lines.append(f'"{key}": {render(v)}')
            elif isinstance(v, list):
                items = ", ".join(f'"{x}"' if isinstance(x, str) else str(x) for x in v)
                lines.append(f'"{key}": [{items}]')
            elif isinstance(v, str):
                lines.append(f'"{key}": "{v}"')
            else:
                lines.append(f'"{key}": {v}')
        return "{\n" + ",\n".join(lines) + "\n}"

    return render(value)


TEMPLATE = """[gd_resource type="Resource" script_class="TerrainObject" load_steps=2 format=3]

[ext_resource type="Script" path="{script}" id="1_script"]

[resource]
script = ExtResource("1_script")
id = "{obj_id}"
cell_type = "{cell_type}"
display_name = "{display_name}"
cells = {cells}
"""


def generate(catalog_path: str, out_dir: str) -> int:
    catalog = json.loads(Path(catalog_path).read_text())
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    written = 0
    for base, fam in sorted(catalog.items()):
        kind = fam["kind"]
        cell_type = KIND_TO_CELL_TYPE[kind]
        for t, direction in enumerate(DIRECTIONS):
            obj_id = f"{base}_{direction}"
            cells_rot = []
            for x, y, height, land, slope in fam["cells"]:
                rx, ry = rotate_cell(x, y, fam["width"], fam["height"], t)
                cells_rot.append((rx, ry, height, land, slope))
            rw = fam["width"] if t in (0, 2) else fam["height"]
            rh = fam["height"] if t in (0, 2) else fam["width"]
            cell_conns = derive_cell_connections(cells_rot, rw, rh, kind)
            cells = {}
            for x, y, height, land, slope in cells_rot:
                key = f"{x},{y}"
                entry: dict = {"land": LAND_MAP.get(land, "clear")}
                # Rotate the slope code along with the cell; the rotated
                # RampType's corner offsets already encode the rotation, so
                # corners = height + offsets[rotated_slope] are the facing
                # corners directly (no extra corner rotation). The stored
                # slope therefore describes exactly the stored corners.
                rotated_slope = rotate_slope(slope, t)
                offsets = _slope_offsets(rotated_slope)
                corners = [height + o for o in offsets]
                entry["corners"] = corners
                entry["crease"] = derive_crease(corners)
                if rotated_slope:
                    entry["slope"] = rotated_slope
                if key in cell_conns:
                    entry["connections"] = cell_conns[key]
                cells[key] = entry
            body = TEMPLATE.format(
                script=TERRAIN_OBJECT_SCRIPT,
                obj_id=obj_id,
                cell_type=cell_type,
                display_name=f"{base.replace('_', ' ').title()} {direction.upper()}",
                cells=indent_dict(cells, 4),
            )
            target = out / f"{obj_id}.tres"
            target.write_text(body)
            written += 1
    print(f"generated {written} TerrainObject variants ({len(catalog)} families x 4)")
    return 0


def _slope_offsets(slope: int) -> list:
    """WAE/FinalSun RampCornerHeights corner offsets for a RampType code."""
    return list(RAMP_CORNER_HEIGHTS.get(slope, [0, 0, 0, 0]))


# Reverse RampType lookup: corner-offset tuple -> slope code that produces it.
# Slopes 17/19 and 18/20 share offsets (geometrically identical); the first code
# wins, and rotation never emits the duplicates.
REVERSE_RAMP: dict[tuple, int] = {}
for _code, _offsets in RAMP_CORNER_HEIGHTS.items():
    REVERSE_RAMP.setdefault(tuple(_offsets), _code)


def rotate_slope(slope: int, t: int) -> int:
    """Rotate a RampType code by transform t so it matches rotated corners."""
    if slope == 0 or t == 0:
        return slope
    offsets = _slope_offsets(slope)
    rotated = rotate_corners(offsets, t)
    return REVERSE_RAMP.get(tuple(rotated), slope)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate TerrainObject tres from the isotem catalog.")
    parser.add_argument("--catalog", default=os.environ.get("CATALOG_PATH", DEFAULT_CATALOG))
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    return generate(args.catalog, args.out)


if __name__ == "__main__":
    raise SystemExit(main())
