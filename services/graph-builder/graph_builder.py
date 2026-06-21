import os
import re
import tempfile
import shutil
from pathlib import Path
from git import Repo
from secret_manager import get_github_token


def parse_python_imports(file_path: str) -> list:
    """
    Extract import statements from a Python file.
    Returns a list of module names being imported.
    """
    imports = []
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                # Match: import os, import sys
                if line.startswith("import "):
                    module = line.replace("import ", "").split(" as ")[0].split(".")[0].strip()
                    imports.append(module)
                # Match: from flask import Flask, from .utils import helper
                elif line.startswith("from "):
                    parts = line.split(" import ")
                    if len(parts) > 0:
                        module = parts[0].replace("from ", "").split(".")[0].strip()
                        if module:
                            imports.append(module)
    except Exception:
        pass
    return imports


def parse_js_imports(file_path: str) -> list:
    """
    Extract import/require statements from a JavaScript or TypeScript file.
    """
    imports = []
    # Matches: import x from 'module' and const x = require('module')
    import_pattern = re.compile(
        r"""(?:import\s+.*?\s+from\s+['"]([^'"]+)['"]|require\s*\(\s*['"]([^'"]+)['"]\s*\))""",
        re.MULTILINE
    )
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            for match in import_pattern.finditer(content):
                module = match.group(1) or match.group(2)
                if module:
                    # Strip relative imports — only keep package imports
                    if not module.startswith("."):
                        # For scoped packages like @org/pkg, keep the full name
                        imports.append(module.split("/")[0] if not module.startswith("@") else "/".join(module.split("/")[:2]))
    except Exception:
        pass
    return imports


def build_graph(repo_url: str) -> dict:
    """
    Clone the repo and build a dependency graph.

    Returns a dict with:
    - nodes: list of {id, label, type} — files and modules
    - edges: list of {source, target} — import relationships
    """
    token = get_github_token()
    temp_dir = tempfile.mkdtemp(prefix="gitflow-graph-")

    try:
        if "github.com" in repo_url:
            authenticated_url = repo_url.replace(
                "https://github.com",
                f"https://{token}@github.com"
            )
        else:
            authenticated_url = repo_url

        try:
            Repo.clone_from(authenticated_url, temp_dir, depth=1)
        except Exception as e:
            raise ValueError(f"Failed to clone repository: {str(e)}")

        nodes = []
        edges = []
        node_ids = set()

        def add_node(node_id: str, label: str, node_type: str):
            if node_id not in node_ids:
                nodes.append({"id": node_id, "label": label, "type": node_type})
                node_ids.add(node_id)

        # Walk the repo and process source files
        for root, dirs, files in os.walk(temp_dir):
            dirs[:] = [
                d for d in dirs
                if not d.startswith(".")
                and d not in ["node_modules", "vendor", "__pycache__", "dist", "build"]
            ]

            for file in files:
                file_path = os.path.join(root, file)
                # Make the file path relative to the repo root for cleaner display
                relative_path = os.path.relpath(file_path, temp_dir)
                file_ext = Path(file).suffix.lower()

                # Only process source files
                if file_ext not in [".py", ".js", ".ts"]:
                    continue

                # Add this file as a node
                file_node_id = relative_path
                add_node(file_node_id, relative_path, "file")

                # Parse imports based on file type
                if file_ext == ".py":
                    imports = parse_python_imports(file_path)
                elif file_ext in [".js", ".ts"]:
                    imports = parse_js_imports(file_path)
                else:
                    imports = []

                # Add each imported module as a node and create an edge
                for module in set(imports):
                    module_node_id = f"module:{module}"
                    add_node(module_node_id, module, "module")
                    edges.append({
                        "source": file_node_id,
                        "target": module_node_id
                    })

        return {
            "repo_url": repo_url,
            "nodes": nodes,
            "edges": edges,
            "node_count": len(nodes),
            "edge_count": len(edges),
            "status": "success"
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
