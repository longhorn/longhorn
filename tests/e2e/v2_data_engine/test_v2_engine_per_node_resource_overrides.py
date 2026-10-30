"""
Test suite for V2 data engine per-node resource override functionality.

Tests validate that per-node resource overrides (CPU, memory) for V2 data engine
instance managers work correctly and take precedence over global settings.
"""

import pytest
import time
from tests.e2e import conftest
from tests.e2e.fixtures import common_fixtures


class TestV2EnginePerNodeResourceOverrides:
    """Test per-node resource overrides for V2 data engine instance managers."""

    @pytest.mark.v2_data_engine
    @pytest.mark.parametrize("num_nodes", [3])
    def test_per_node_override_priority_over_global(self, client, num_nodes):
        """
        Verify that per-node CPU override takes priority over global setting.

        Given: Global V2DataEngineGuaranteedInstanceManagerCPU = 10%
        When: Node has per-node override to 20%
        Then: Instance manager pod should use 20% (per-node value)
        """
        # Setup: Get nodes and set global setting
        nodes = client.list_node()["items"]
        assert len(nodes) >= num_nodes, f"Cluster has {len(nodes)} nodes, need {num_nodes}"

        # Set global V2 guaranteed instance manager CPU to 10%
        self.set_v2_guarantee_setting(client, "10")

        # Apply per-node override on first node to 20%
        override_node = nodes[0]
        self.apply_node_cpu_override(client, override_node["metadata"]["name"], "20")

        # Give system time to propagate
        time.sleep(5)

        # Verify: Check instance manager pod resources on override node
        pod_resources = self.get_instance_manager_pod_resources(
            client, override_node["metadata"]["name"]
        )
        assert pod_resources is not None, "Instance manager pod not found"

        # Expected: Pod should have 20% CPU (per-node override)
        assert self.cpu_matches_override(pod_resources, "20"), (
            f"Pod CPU request {pod_resources.get('cpu')} "
            "does not match per-node override of 20%"
        )

    @pytest.mark.v2_data_engine
    def test_global_v2_guaranteed_instance_manager_cpu(self, client):
        """
        Verify that global V2DataEngineGuaranteedInstanceManagerCPU setting applies.

        Given: Global V2DataEngineGuaranteedInstanceManagerCPU = 15%
        When: No per-node overrides exist
        Then: All instance manager pods should use 15%
        """
        nodes = client.list_node()["items"]

        # Set global setting to 15%
        self.set_v2_guarantee_setting(client, "15")
        time.sleep(5)

        # Verify all nodes use global setting
        for node in nodes:
            pod_resources = self.get_instance_manager_pod_resources(
                client, node["metadata"]["name"]
            )
            if pod_resources:  # Skip nodes without v2 volumes
                assert self.cpu_matches_value(pod_resources, "15"), (
                    f"Node {node['metadata']['name']} pod CPU {pod_resources.get('cpu')} "
                    "does not match global setting of 15%"
                )

    @pytest.mark.v2_data_engine
    def test_per_node_override_persistence_across_setting_updates(self, client):
        """
        Verify per-node overrides persist when global setting changes.

        Given: Per-node override = 25%, Global = 10%
        When: Global setting changes to 30%
        Then: Per-node should still be 25% (override persists)
        """
        nodes = client.list_node()["items"]
        node_name = nodes[0]["metadata"]["name"]

        # Setup per-node override
        self.apply_node_cpu_override(client, node_name, "25")
        self.set_v2_guarantee_setting(client, "10")
        time.sleep(5)

        # Verify per-node override applies
        pod_resources = self.get_instance_manager_pod_resources(client, node_name)
        assert self.cpu_matches_override(pod_resources, "25"), "Initial override not applied"

        # Change global setting to 30%
        self.set_v2_guarantee_setting(client, "30")
        time.sleep(5)

        # Verify per-node override still applies (not affected by global change)
        pod_resources = self.get_instance_manager_pod_resources(client, node_name)
        assert self.cpu_matches_override(pod_resources, "25"), (
            "Per-node override was overridden by global setting change"
        )

    @pytest.mark.v2_data_engine
    def test_v2_volumes_with_per_node_resource_overrides(self, client):
        """
        Verify V2 volumes work correctly with per-node resource overrides.

        Given: V2 volumes created on nodes with different CPU overrides
        When: Volumes are actively used
        Then: Volumes should function normally with correct resource limits
        """
        nodes = client.list_node()["items"]
        if len(nodes) < 2:
            pytest.skip("Test requires at least 2 nodes")

        # Setup different overrides on different nodes
        self.apply_node_cpu_override(client, nodes[0]["metadata"]["name"], "15")
        self.apply_node_cpu_override(client, nodes[1]["metadata"]["name"], "25")

        time.sleep(10)

        # Create V2 volumes on different nodes
        volume1_name = "test-v2-override-vol-1"
        volume2_name = "test-v2-override-vol-2"

        self.create_v2_volume(client, volume1_name, nodes[0]["metadata"]["name"])
        self.create_v2_volume(client, volume2_name, nodes[1]["metadata"]["name"])

        time.sleep(15)

        # Verify volumes are healthy and attached
        vol1_state = client.get_volume(volume1_name)
        vol2_state = client.get_volume(volume2_name)

        assert vol1_state.get("status", {}).get("state") == "attached", (
            f"Volume {volume1_name} not attached on node with 15% override"
        )
        assert vol2_state.get("status", {}).get("state") == "attached", (
            f"Volume {volume2_name} not attached on node with 25% override"
        )

    # Helper methods

    def set_v2_guarantee_setting(self, client, cpu_percentage):
        """Set global V2DataEngineGuaranteedInstanceManagerCPU setting."""
        # Implementation depends on how settings are exposed (API, CRD, etc.)
        # This is a placeholder showing the intended interface
        pass

    def apply_node_cpu_override(self, client, node_name, cpu_percentage):
        """Apply per-node CPU override for V2 instance manager."""
        # Implementation depends on Node CRD structure
        # Placeholder showing intended interface
        pass

    def get_instance_manager_pod_resources(self, client, node_name):
        """Get instance manager pod resource requests for a node."""
        # Retrieve pod and extract resource requests
        # Returns dict with cpu, memory keys
        pass

    def cpu_matches_override(self, pod_resources, expected_override):
        """Check if pod CPU matches expected per-node override."""
        pass

    def cpu_matches_value(self, pod_resources, expected_value):
        """Check if pod CPU matches expected value."""
        pass

    def create_v2_volume(self, client, volume_name, node_name):
        """Create a V2 data engine volume pinned to a specific node."""
        # Create volume with V2 data engine and node affinity
        pass
