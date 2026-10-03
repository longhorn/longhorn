import shutil
import subprocess
import unittest
from pathlib import Path

import yaml


CHART = Path(__file__).resolve().parents[1]


class TestUIReadiness(unittest.TestCase):
    def render(self, *settings):
        helm = shutil.which("helm")
        self.assertIsNotNone(helm, "helm must be installed to run chart tests")
        command = [
            helm, "template", "longhorn", str(CHART),
            "--namespace", "longhorn-system",
            "--show-only", "templates/deployment-ui.yaml",
        ]
        for setting in settings:
            command.extend(["--set", setting])
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        deployment = next(
            doc for doc in yaml.safe_load_all(result.stdout)
            if doc and doc.get("kind") == "Deployment"
            and doc["metadata"]["name"] == "longhorn-ui"
        )
        containers = deployment["spec"]["template"]["spec"]["containers"]
        ui = next(container for container in containers
                  if container["name"] == "longhorn-ui")
        return ui, containers

    def test_disabled_by_default(self):
        ui, _ = self.render()
        self.assertNotIn("readinessProbe", ui)

    def test_enabled_checks_api_on_ui_port(self):
        ui, _ = self.render("longhornUI.readinessProbe.enabled=true")
        probe = ui.get("readinessProbe")
        self.assertIsNotNone(probe)
        self.assertEqual(probe["httpGet"], {"path": "/v1", "port": 8000})
        self.assertEqual(probe["initialDelaySeconds"], 1)
        self.assertEqual(probe["periodSeconds"], 1)
        self.assertEqual(probe["timeoutSeconds"], 1)
        self.assertEqual(probe["successThreshold"], 1)
        self.assertEqual(probe["failureThreshold"], 3)
        self.assertNotIn("enabled", probe)
        self.assertIn(8000, [port["containerPort"] for port in ui["ports"]])

    def test_probe_settings_can_be_overridden(self):
        ui, _ = self.render(
            "longhornUI.readinessProbe.enabled=true",
            "longhornUI.readinessProbe.httpGet.path=/",
            "longhornUI.readinessProbe.periodSeconds=5",
            "longhornUI.readinessProbe.timeoutSeconds=3",
            "longhornUI.readinessProbe.failureThreshold=2",
        )
        probe = ui.get("readinessProbe")
        self.assertIsNotNone(probe)
        self.assertEqual(probe["httpGet"], {"path": "/", "port": 8000})
        self.assertEqual(probe["periodSeconds"], 5)
        self.assertEqual(probe["timeoutSeconds"], 3)
        self.assertEqual(probe["failureThreshold"], 2)
        self.assertNotIn("enabled", probe)

    def test_openshift_probe_is_on_ui_container(self):
        ui, containers = self.render(
            "longhornUI.readinessProbe.enabled=true",
            "openshift.enabled=true",
            "openshift.ui.route=longhorn-ui",
        )
        oauth = next(container for container in containers
                     if container["name"] == "oauth-proxy")
        self.assertNotIn("readinessProbe", oauth)
        self.assertEqual(ui.get("readinessProbe", {}).get("httpGet"),
                         {"path": "/v1", "port": 8000})

    def test_null_probe_is_disabled(self):
        ui, _ = self.render("longhornUI.readinessProbe=null")
        self.assertNotIn("readinessProbe", ui)


if __name__ == "__main__":
    unittest.main()
