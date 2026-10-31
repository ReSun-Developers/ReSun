class_name HitboxComponent extends Area3D

## Collision layers — assign via EntityFactory based on entity type.
const LAYER_HITBOX_GROUND: int = 1 << 1
const LAYER_HITBOX_AIR: int = 1 << 2
const LAYER_HITBOX_BUILDING: int = 1 << 3
const LAYER_PROJECTILE: int = 1 << 4

## Retained for entity wiring compatibility; damage no longer flows through the hitbox.
@export var health_component: HealthComponent
@export var size: Vector3 = Vector3(2.0, 2.0, 2.0):
    set(value):
        size = value
        _update_collision_shape()


func _update_collision_shape() -> void:
    $CollisionObject3D.shape.size = size
    $CollisionObject3D.position = Vector3(0, size.y / 2.0, 0)
