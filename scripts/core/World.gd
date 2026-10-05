class_name World extends Node3D

## World — the per-match container. MissionBoot creates one for each match and
## hosts the loaded MissionMap inside it, so all per-match scene content has a
## single teardown owner. Runtime-spawned content (produced units, built
## structures, projectiles, effects, grown resources) is parented under it
## through `spawn` / `spawn_container`, so a match swap releases everything.
##
## `spawn_container` is the single access seam every runtime spawner uses. It
## resolves the live match World root and falls back to an explicit parent, then
## the current scene, then the scene tree root, so content spawned outside a match
## (headless tests, the map editor) still has a valid parent and is never dropped.

## Runtime content container under the World root.
enum Bucket { ENTITIES, EFFECTS }

const ENTITIES_NAME: String = "Entities"
const EFFECTS_NAME: String = "Effects"

## The live match World root, or null between matches / when none is valid.
static var _active: World = null

var _buckets: Dictionary = {}


func _enter_tree() -> void:
    _active = self


func _exit_tree() -> void:
    if _active == self:
        _active = null


## The live match World root, or null when none is present, detached, or queued
## for deletion. Never returns a stale reference to an outgoing match.
static func get_active() -> World:
    if (
        is_instance_valid(_active)
        and _active.is_inside_tree()
        and not _active.is_queued_for_deletion()
    ):
        return _active
    return null


## Resolves the parent node for runtime-spawned content in `bucket`: the live
## match World when present, otherwise `fallback`, then the current scene, then
## the scene tree root. Returns null only when there is no scene tree.
static func spawn_container(bucket: Bucket, fallback: Node = null) -> Node:
    var world := get_active()
    if world != null:
        return world._bucket(bucket)
    if fallback != null and is_instance_valid(fallback):
        return fallback
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return null
    if tree.current_scene != null:
        return tree.current_scene
    return tree.root


## Parents `node` under this match's World in `bucket` and returns it.
func spawn(node: Node, bucket: Bucket = Bucket.ENTITIES) -> Node:
    _bucket(bucket).add_child(node)
    return node


## The container node for `bucket`, created lazily on first use.
func _bucket(bucket: Bucket) -> Node3D:
    var existing: Node = _buckets.get(bucket)
    if existing != null and is_instance_valid(existing):
        return existing as Node3D
    var node := Node3D.new()
    node.name = ENTITIES_NAME if bucket == Bucket.ENTITIES else EFFECTS_NAME
    add_child(node)
    _buckets[bucket] = node
    return node
