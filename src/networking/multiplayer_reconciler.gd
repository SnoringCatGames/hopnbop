@tool
class_name MultiplayerReconciler
extends MultiplayerSynchronizer


# FIXME: LEFT OFF HERE:
# -


enum AuthorityMode {
    STATE_FROM_SERVER,
    INPUT_FROM_CLIENT,
}


@export var authority_mode := AuthorityMode.STATE_FROM_SERVER:
    set(value):
        authority_mode = value
        _update_partner_reconciler()

## Which machine this state is associated with.
##
## - This is the client machine that would be given authority to INPUT_FROM_CLIENT.
## - An ID of 1 represents the server.
## - This is automatically assigned according to the replication configuration
##   defined on the corresponding STATE_FROM_SERVER reconciler. However, this
##   will only be assigned if this is an INPUT_FROM_CLIENT reconciler, or there
##   is an accompanying INPUT_FROM_CLIENT reconciler.
var _multiplayer_id := 1

## STATE_FROM_SERVER reconciler and INPUT_FROM_CLIENT reconciler nodes are often
## used as a pair to send input state from a client machine to the server and to
## then send all other networked state from the server to all clients.
##
## In this scenario, _partner_reconciler is the other node from this pair.
var _partner_reconciler: MultiplayerReconciler

var _partner_reconciler_configuration_warning := ""

var root: Node:
    get: return get_node_or_null(root_path)


func _ready() -> void:
    _update_partner_reconciler()

    if Engine.is_editor_hint():
        return

    # Only collect input from the authoritative client.
    if authority_mode == AuthorityMode.INPUT_FROM_CLIENT:
        set_process(is_multiplayer_authority())

    pass
    #multiplayer.get_unique_id()
    #set_multiplayer_authority()
    #replication_config


func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return

    pass


func _update_partner_reconciler() -> void:
    _partner_reconciler = null

    # Collect all sibling reconcilers.
    var sibling_reconcilers: Array[MultiplayerReconciler] = []
    for child in get_parent().get_children():
        if child is MultiplayerReconciler and child != self:
            sibling_reconcilers.push_back(child)

    # Record the sibling, and validate the node configuration.
    if sibling_reconcilers.size() == 1:
        if sibling_reconcilers[0].authority_mode != authority_mode:
            _partner_reconciler = sibling_reconcilers[0]
        elif authority_mode == AuthorityMode.STATE_FROM_SERVER:
            _partner_reconciler_configuration_warning = \
                "You should consolidate sibling STATE_FROM_SERVER nodes (or should one be INPUT_FROM_CLIENT?)."
        else:
            _partner_reconciler_configuration_warning = \
                "There should only be one INPUT_FROM_CLIENT node here (should one be STATE_FROM_SERVER?)."
    elif sibling_reconcilers.size() > 1:
        _partner_reconciler_configuration_warning = \
            "There should be no more than 2 reconcilers in a given place--one INPUT_FROM_CLIENT and one STATE_FROM_SERVER."
    elif authority_mode == AuthorityMode.INPUT_FROM_CLIENT:
        _partner_reconciler_configuration_warning = \
            "An INPUT_FROM_CLIENT reconciler must be accompanied by a STATE_FROM_SERVER reconciler sibling node."

    if is_instance_valid(_partner_reconciler):
        var state_from_server_reconciler: MultiplayerReconciler = \
            self if authority_mode == AuthorityMode.STATE_FROM_SERVER else _partner_reconciler
        var state_from_server_config := state_from_server_reconciler.replication_config

        # Find the multiplayer_id_path from the STATE_FROM_SERVER reconciler config.
        var multiplayer_id_path: NodePath = ""
        for property_path in state_from_server_config.get_properties():
            var last_subname := property_path.get_subname(property_path.get_subname_count() - 1)
            if last_subname == "multiplayer_id":
                multiplayer_id_path = property_path

        # Parse the property value from multiplayer_id_path.
        if not multiplayer_id_path.is_empty():
            var multiplayer_id = Utils.get_property_value_from_node_path(
                state_from_server_reconciler.root, multiplayer_id_path)
            if multiplayer_id is int:
                _multiplayer_id = multiplayer_id
            elif multiplayer_id == null:
                _partner_reconciler_configuration_warning = \
                    "The `multiplayer_id` property defined in STATE_FROM_SERVER was not found."
            else:
                _partner_reconciler_configuration_warning = \
                    "The `multiplayer_id` property replicated by STATE_FROM_SERVER must be an int."
        else:
            _partner_reconciler_configuration_warning = \
                "STATE_FROM_SERVER reconciler must replicate a `multiplayer_id` property."

    update_configuration_warnings()

    if not Engine.is_editor_hint() and \
            not _partner_reconciler_configuration_warning.is_empty():
        # Log and assert in game runtime environments.
        G.log.error("MultiplayerReconciler is misconfigured: %s" % _partner_reconciler_configuration_warning)


func _get_configuration_warnings() -> PackedStringArray:
    if not Engine.is_editor_hint():
        return []

    var warnings: PackedStringArray = []

    if not _partner_reconciler_configuration_warning.is_empty():
        warnings.append(_partner_reconciler_configuration_warning)

    return warnings
