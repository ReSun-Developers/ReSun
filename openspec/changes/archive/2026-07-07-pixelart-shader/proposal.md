## Why

The 3D world currently renders at native resolution with no stylization. A pixel art post-processing shader with depth-based entity outlines will give ReSun a retro aesthetic matching Tiberian Sun's pixel art heritage, while keeping the UI crisp at native resolution.

## What Changes

- New fullscreen spatial shader: pixelates the 3D render and draws black outlines at depth discontinuities, masked to playable entities (and opt-in props) via a dedicated render layer
- New EntityMaskManager autoload singleton: creates a SubViewport (1280×720) that renders layer 2 only (unshaded white), syncs a mask camera to the main camera each frame, and pushes the mask texture to the shader material
- New PixelArtPostProcess01.tscn scene: MeshInstance3D with QuadMesh (2×2, flip faces) using the shader, placed as child of the Camera3D
- All existing entity scenes (NodBuggy, GDIConyard, CivilianGuardTower, TempInfantry) get render layer 2 enabled on their meshes so they appear in the entity mask
- Any future entity or prop can opt into outlines by enabling layer 2 in the editor — no code changes needed

## Capabilities

### New Capabilities
- `pixelart-postprocess`: Fullscreen pixelation shader with depth-edge detection and entity-masked outline rendering

### Modified Capabilities

None — no existing specs are changing.

## Impact

- **New files**: 1 shader, 1 scene, 1 autoload script
- **Modified files**: project.godot (autoload registration), Camera01.tscn (add child scene), 4 entity .tscn files (layer 2 toggle)
- **No existing behavior changed**: selection, movement, camera controls, and UI are unaffected
- **Performance**: SubViewport renders layer 2 at 1280×720 each frame — lightweight entity mask pass with no materials/lights