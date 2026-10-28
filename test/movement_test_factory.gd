## Builds a detached MovementController from the same Locomotor resource
## production uses, instead of hand-setting the mirrored flags. The returned
## controller's parent is the entity root (`mc.get_parent()`).

static func make_movement_controller(
    locomotor: Locomotor,
    entity_type: int = EntityData.EntityType.INFANTRY,
    player_id: int = 0,
) -> MovementController:
    var entity := Node3D.new()
    var stats := StatsComponent.new()
    stats.name = "StatsComponent"
    stats.entity_type = entity_type
    stats.player_id = player_id
    stats.weight = 3.0
    entity.add_child(stats)
    var mc := MovementController.new()
    mc.name = "MovementController"
    entity.add_child(mc)
    mc._parent = entity
    mc.apply_locomotor(locomotor)
    return mc
