## Context

The current game renders 3D at full 1920×1080 with standard PBR materials — no stylization. To achieve a Tiberian Sun pixel-art aesthetic, we need a post-processing pass that pixelates the 3D world and draws outlines selectively on entities (units, structures, infantry, opt-in props), while keeping the UI layer (Control nodes) crisp.

## Goals / Non-Goals

**Goals:**
- Fullscreen pixelation of the 3D world render (UI unaffected)
- Depth-based outlines at 50% opacity on playable entities and opt-in props
- Mask-based approach using a dedicated render layer (layer 2) and a SubViewport at 1280×720
- Autoload singleton (EntityMaskManager) to manage the mask SubViewport, camera sync, and texture assignment
- Zero changes to existing gameplay logic (selection, movement, camera controls)

**Non-Goals:**
- Per-entity outline color/fidelity variation (all outlined entities use the same color)
- Posterization, dithering, or palette limitation (may be added later as separate work)
- Outline animation or pulsing effects
- UI pixelation (Control nodes stay at native resolution)

## Decisions

1. **QuadMesh fullscreen approach vs CompositorEffect**: QuadMesh with vertex shader (`POSITION = vec4(VERTEX.xy, 1.0, 1.0)`) is simpler, requires no RenderingDevice boilerplate, and works identically in Redot 26.2 Forward+. CompositorEffect is more powerful but overkill for a single-pass screen-read + mask blend.

2. **SubViewport mask at 1280×720**: Chosen as a middle ground between accuracy and performance. Native res (1920×1080) would be more precise but doubles the fill cost. The mask only renders unshaded white geometry on a single layer — no lights, no materials — so it's extremely cheap even at this resolution. The `filter_nearest` sampler on the mask texture aligns naturally with pixel blocks.

3. **Render layer 2 for entity masking**: Layer-based approach requires minimal per-entity setup (one checkbox in the editor per MeshInstance3D) and scales to any number of entities and future props. No stencil buffer complexity, no custom renderer features. Entities default to layer 1, so adding layer 2 is additive.

4. **EntityMaskManager as autoload singleton**: Needs to exist for the full lifetime of Gameplay, must access the QuadMesh material to push the mask texture uniform, and needs to sync the mask camera every `_process()` frame. Autoload is the simplest way to guarantee availability without coupling to any scene lifecycle.

5. **Pixelation via texelFetch + block snapping**: Integer UV snapping to `pixel_size` blocks, then sampling the center pixel of each block with `texelFetch`. This avoids the bilinear-filter artifacts of UV-based rounding and produces perfectly sharp pixel blocks. `filter_nearest` on the screen texture uniform enforces crisp sampling.

6. **Depth edge detection with 4-tap kernel**: Up/down/left/right offsets at `pixel_size` stride. No diagonal taps — they add cost with marginal benefit for pixel-art outlines. `smoothstep` on the depth difference produces a smooth transition rather than a hard cut.

## Risks / Trade-offs

- **Mask resolution mismatch**: The mask SubViewport is 1280×720 while the main viewport is 1920×1080. At `pixel_size=4`, the effective pixel-block resolution is ~480×270. The mask is sampled at block-center UVs, so the 1280×720 mask is still ~2.7× oversampled relative to pixel blocks — no visible mismatch.

- **Camera sync latency**: Mask camera syncs every `_process()` (not `_physics_process`), so it's one frame behind the main camera at most. For orthogonal projection with smooth camera movement, this delay is invisible.

- **SubViewport creation at runtime**: EntityMaskManager creates the SubViewport and Camera3D in `_ready()` — they have no .tscn representation. This is intentional (avoids scene clutter) but means the mask camera won't appear in the editor Scene tree. Debugging mask issues requires runtime inspection.

- **Depth edge detection on flat ground**: If entities sit on a flat GroundPlane at the same depth, the 4-tap kernel won't detect the entity-ground boundary (no depth discontinuity). This is acceptable — entity silhouettes against terrain still get outlines from their own depth edges (arms, turrets, height variations), and the ground plane is effectively depth-flat. If this proves insufficient, a normal-based edge detection pass can be added later.

- **No outline on terrain/buildings that share depth**: Two structures flush against each other at identical depth won't show a boundary outline. This matches the pixel-art aesthetic (entities are outlined, world edges are not) and is a conscious non-goal to fix.