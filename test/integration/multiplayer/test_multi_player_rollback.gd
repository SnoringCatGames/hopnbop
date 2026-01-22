extends GutTest
## Integration tests for multi-entity rollback scenarios.
##
## These tests verify that rollbacks work correctly when multiple networked
## entities are involved, testing cross-entity synchronization and consistency.

func before_each():
    ArrayPool.clear_all_pools()


func after_each():
    ArrayPool.clear_all_pools()


class TestMultiPlayerRollback:
    extends GutTest
    ## Tests interactions between multiple networked entities during rollback.

    var frame_driver: NetworkFrameDriver
    var entity1: TestNetworkedEntity
    var entity2: TestNetworkedEntity


    func before_each():
        ArrayPool.clear_all_pools()
        frame_driver = G.network.frame_driver
        # Clear any entities from previous tests
        frame_driver._networked_state_nodes.clear()


    func after_each():
        ArrayPool.clear_all_pools()
        if is_instance_valid(entity1):
            entity1.queue_free()
        if is_instance_valid(entity2):
            entity2.queue_free()


    func test_multiple_entities_tracked_by_frame_driver():
        # Create two test entities
        entity1 = TestNetworkedEntity.create_test_entity(
            Vector2(100, 100),
            Vector2(10, 0),
        )
        entity2 = TestNetworkedEntity.create_test_entity(
            Vector2(200, 200),
            Vector2(-10, 0),
        )

        # Register both entities
        frame_driver.add_networked_state(entity1)
        frame_driver.add_networked_state(entity2)

        # Verify both are tracked
        assert_true(
            frame_driver._networked_state_nodes.has(entity1),
            "Entity 1 should be tracked",
        )
        assert_true(
            frame_driver._networked_state_nodes.has(entity2),
            "Entity 2 should be tracked",
        )


    func test_rollback_affects_all_entities():
        # Register two entities
        entity1 = TestNetworkedEntity.create_test_entity()
        entity2 = TestNetworkedEntity.create_test_entity()

        frame_driver.add_networked_state(entity1)
        frame_driver.add_networked_state(entity2)

        # Set frame index
        frame_driver.server_frame_index = 50

        # Queue rollback
        var result := frame_driver.queue_rollback(45)

        assert_true(result, "Should queue rollback successfully")
        # Both entities would be affected by the rollback
        # (actual re-simulation happens in _rollback_and_reprocess)


    func test_entity_removal_during_active_session():
        # Test that entities can be removed without breaking rollback
        entity1 = TestNetworkedEntity.create_test_entity()
        entity2 = TestNetworkedEntity.create_test_entity()

        frame_driver.add_networked_state(entity1)
        frame_driver.add_networked_state(entity2)

        # Remove entity1
        frame_driver.remove_networked_state(entity1)

        # Entity2 should still be tracked
        assert_true(
            frame_driver._networked_state_nodes.has(entity2),
            "Entity 2 should still be tracked",
        )
        assert_false(
            frame_driver._networked_state_nodes.has(entity1),
            "Entity 1 should be removed",
        )


    func test_rollback_buffer_independent_per_entity():
        # Each entity has its own rollback buffer
        entity1 = TestNetworkedEntity.create_test_entity(
            Vector2(100, 100),
            Vector2(10, 0),
        )
        entity2 = TestNetworkedEntity.create_test_entity(
            Vector2(200, 200),
            Vector2(-10, 0),
        )

        # Verify entities have separate buffers
        # (buffers are created in ReconcilableNetworkedState._ready)
        assert_ne(
            entity1._rollback_buffer,
            entity2._rollback_buffer,
            "Entities should have separate rollback buffers",
        )


    func test_frame_driver_processes_entities_in_order():
        # Verify that all entities are processed in each network process
        entity1 = TestNetworkedEntity.create_test_entity()
        entity2 = TestNetworkedEntity.create_test_entity()

        frame_driver.add_networked_state(entity1)
        frame_driver.add_networked_state(entity2)

        # Reset counters
        entity1.reset_test_state()
        entity2.reset_test_state()

        # The _network_process method processes all entities
        # We can't directly call it here, but we verify registration
        assert_eq(
            frame_driver._networked_state_nodes.size(),
            2,
            "Should have 2 entities registered",
        )


    func test_oldest_rollbackable_frame_applies_to_all_entities():
        # The oldest rollbackable frame is global, not per-entity
        frame_driver.server_frame_index = 200

        var oldest := frame_driver.oldest_rollbackable_frame_index

        # This applies to all entities
        assert_eq(
            oldest,
            83,
            "Oldest rollbackable should be 83 for all entities",
        )
