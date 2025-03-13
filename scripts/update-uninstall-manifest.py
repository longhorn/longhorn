import yaml
import os
from typing import List, Dict, Iterator
from pathlib import Path

class YAMLResourceProcessor:
    def __init__(self, longhorn_manifest: str, uninstall_file: str):
        self.longhorn_manifest = Path(longhorn_manifest)
        self.uninstall_file = Path(uninstall_file)
        self.output_file = self.uninstall_file.parent / 'uninstall.tmp.yaml'

    def load_yaml_documents(self, file_path: Path) -> Iterator[Dict]:
        """Load YAML documents from a file, skipping None values."""
        try:
            with open(file_path, 'r') as file:
                for doc in yaml.safe_load_all(file):
                    if doc is not None:
                        yield doc
        except (yaml.YAMLError, OSError) as e:
            raise RuntimeError(f"Error processing {file_path}: {str(e)}")

    def extract_crd_resources(self) -> List[str]:
        """Extract CustomResourceDefinition names from the manifest."""
        resources = []
        for doc in self.load_yaml_documents(self.longhorn_manifest):
            if doc.get('kind') == "CustomResourceDefinition":
                name = doc.get('metadata', {}).get('name', '')
                if name:
                    # Remove '.longhorn.io' suffix
                    resources.append(name.split(".")[0])
        return resources

    def update_cluster_role(self, doc: Dict, resources: List[str]) -> Dict:
        """Update ClusterRole document with new resources."""
        if doc['kind'] == "ClusterRole":
            for rule in doc.get('rules', []):
                if rule.get('apiGroups') == ["longhorn.io"]:
                    rule['resources'] = resources
        return doc

    def process_files(self) -> None:
        """Process the input files and generate the output file."""
        resources = self.extract_crd_resources()

        try:
            with open(self.output_file, 'w') as output:
                for doc in self.load_yaml_documents(self.uninstall_file):
                    updated_doc = self.update_cluster_role(doc, resources)
                    yaml.dump(updated_doc, output)
                    output.write('---\n')
        except (yaml.YAMLError, OSError) as e:
            raise RuntimeError(f"Error writing output file: {str(e)}")

def main():
    try:
        processor = YAMLResourceProcessor(
            longhorn_manifest='deploy/longhorn.yaml',
            uninstall_file='uninstall/uninstall.yaml'
        )
        processor.process_files()
        # Replace the original file with the updated file
        os.replace(processor.output_file, processor.uninstall_file)
        print("YAML processing completed successfully.")
    except Exception as e:
        print(f"Error: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()