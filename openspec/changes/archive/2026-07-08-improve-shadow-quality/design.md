## Context

The project uses an orthogonal Camera3D for RTS-style gameplay. Shadows are currently blocky because:
- `Camera3D.far = 5000.0` spreads the shadow map across 5000 units of depth
- DirectionalLight3D uses PSSM 4-split (default), designed for perspective cameras
- `light_angular_distance = 1.1` and `shadow_blur = 0.9` add softness inappropriate for sharp RTS shadows
- Shadow map size is at engine default (2048)

The actual gameplay area is ~512×512 units (from `BoundsSystem` configuration in `MapBase01.tscn`).

## Goals / Non-Goals

**Goals:**
- Achieve crisp, high-quality shadows for orthogonal RTS camera
- Concentrate shadow resolution on the visible gameplay area
- Maintain or improve current performance

**Non-Goals:**
- Changing shadow behavior for perspective cameras (not used)
- Implementing dynamic shadow quality settings
- Modifying entity shadow casting (already optimized in `SelectComponent.gd`)

## Decisions

### 1. Camera3D.far = 400.0

**Decision**: Reduce `far` from 5000.0 to 400.0

**Rationale**: The map is 512×512 units. With an isometric view at 45°, the visible depth is ~350 units. A `far` value of 400 provides margin while concentrating shadow resolution. Values below 300 risk clipping terrain at map edges.

**Alternatives considered**:
- `far = 200`: Too aggressive, clips terrain at edges
- `far = 500`: Safe but dilutes shadow quality unnecessarily
- Dynamic `far` based on zoom: Over-engineered for current needs

### 2. Shadow Mode = Orthogonal (0)

**Decision**: Set `directional_shadow_mode = 0` on DirectionalLight3D

**Rationale**: PSSM 4-split divides the frustum into 4 cascades for perspective cameras. Orthogonal mode dedicates the full shadow map to the visible area, which is optimal for our orthogonal RTS view.

**Alternatives considered**:
- PSSM 2-split: Better than 4-split for orthogonal, but still suboptimal
- Keep PSSM 4: Wastes 75% of shadow map on off-screen cascades

### 3. light_angular_distance = 0

**Decision**: Set `light_angular_distance` to 0

**Rationale**: Non-zero values simulate sun disc size, which softens shadow edges. For sharp RTS shadows, perfectly parallel light rays are preferred.

### 4. shadow_blur = 0.1

**Decision**: Reduce `shadow_blur` from 0.9 to 0.1

**Rationale**: Near-zero blur gives crisp shadow edges. 0.1 (not 0.0) avoids harsh pixel-level artifacts on diagonal edges.

### 5. Shadow Map Size = 4096

**Decision**: Set `rendering/lights_and_shadows/directional_shadow/size = 4096` in project.godot

**Rationale**: Doubles shadow resolution from default 2048. 8192 would be sharper but the performance cost is disproportionate given the other optimizations.

## Risks / Trade-offs

- **[Risk] Objects beyond far clip invisible** → Mitigated by choosing 400 (covers full map diagonal). If maps grow beyond 512×512, `far` must be increased proportionally.
- **[Risk] LOD bug (Godot #73472)** → Orthogonal cameras may pick lowest LOD for shadow casting. Fixed in Godot 4.3 (PR #92287). Verify Redot 26.2 includes this fix; if not, disable "Generate LODs" on .glb imports.
- **[Trade-off] Larger shadow map = more GPU memory** → 4096 shadow map uses ~64MB VRAM. Acceptable for modern GPUs; the `far` reduction offsets this by rendering fewer objects.
