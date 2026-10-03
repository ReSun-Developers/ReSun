extends Node3D

## World — the per-match container. MissionBoot creates one for each match and
## hosts the loaded MissionMap inside it, so all per-match scene content has a
## single teardown owner. Later waves move the per-map gameplay systems here as
## scene-scoped children; autoloads are untouched by this node.
