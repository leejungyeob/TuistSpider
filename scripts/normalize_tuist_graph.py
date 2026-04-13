#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def dump_json(data: Any, output_path: str | None) -> None:
    payload = json.dumps(data, ensure_ascii=False, indent=2)
    if output_path:
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.write("\n")
        return
    sys.stdout.write(payload)
    sys.stdout.write("\n")


def pair_projects(projects: Any) -> list[tuple[str, dict[str, Any]]]:
    if isinstance(projects, dict):
        return [(path, project) for path, project in projects.items()]
    if isinstance(projects, list):
        pairs: list[tuple[str, dict[str, Any]]] = []
        for index in range(0, len(projects), 2):
            path = projects[index]
            project = projects[index + 1]
            pairs.append((path, project))
        return pairs
    raise ValueError("Unsupported Tuist projects payload")


def iter_targets(project: dict[str, Any]) -> list[dict[str, Any]]:
    targets = project.get("targets", {})
    if isinstance(targets, dict):
        return list(targets.values())
    if isinstance(targets, list):
        return targets
    return []


def normalize_path(base_path: str, maybe_path: str | None) -> str:
    if not maybe_path:
        return base_path
    if os.path.isabs(maybe_path):
        return os.path.normpath(maybe_path)
    return os.path.normpath(os.path.join(base_path, maybe_path))


def normalize_root_path(path: str | None) -> str | None:
    if not path:
        return None
    return os.path.normpath(path)


def is_external_project_path(project_path: str, root_path: str | None) -> bool:
    normalized_path = os.path.normpath(project_path)
    path_parts = {part.lower() for part in normalized_path.split(os.sep) if part}
    external_markers = {
        "checkouts",
        "sourcepackages",
        "swiftpackagemanager",
        ".build",
        ".cache",
        "cocoapods",
        "carthage",
    }

    if path_parts & external_markers:
        return True

    if not root_path:
        return False

    normalized_root = os.path.normpath(root_path)
    if normalized_path == normalized_root:
        return False

    root_prefix = normalized_root if normalized_root.endswith(os.sep) else normalized_root + os.sep
    return not normalized_path.startswith(root_prefix)


def target_node_id(project_path: str, target_name: str) -> str:
    return f"target::{project_path}::{target_name}"


def external_node_id(kind: str, name: str) -> str:
    return f"{kind}::{name}"


def dependency_name_from_payload(payload: Any) -> str | None:
    if isinstance(payload, str):
        return payload
    if not isinstance(payload, dict):
        return None
    for key in ("name", "product", "target", "path"):
        value = payload.get(key)
        if isinstance(value, str) and value:
            return os.path.basename(value) if key == "path" else value
    return None


def dependency_descriptor(
    dependency: dict[str, Any],
    current_project_path: str,
    root_path: str | None,
) -> dict[str, Any] | None:
    if not isinstance(dependency, dict):
        return None

    if "target" in dependency:
        payload = dependency["target"] or {}
        name = payload.get("name")
        if not name:
            return None
        project_path = normalize_path(current_project_path, payload.get("path"))
        is_external = is_external_project_path(project_path, root_path)
        return {
            "id": target_node_id(project_path, name),
            "kind": "target",
            "name": name,
            "displayName": name,
            "projectPath": project_path,
            "isExternal": is_external,
            "status": payload.get("status"),
        }

    if "project" in dependency:
        payload = dependency["project"] or {}
        name = payload.get("target") or payload.get("name")
        if not name:
            return None
        project_path = normalize_path(current_project_path, payload.get("path"))
        is_external = is_external_project_path(project_path, root_path)
        return {
            "id": target_node_id(project_path, name),
            "kind": "target",
            "name": name,
            "displayName": name,
            "projectPath": project_path,
            "isExternal": is_external,
            "status": payload.get("status"),
        }

    for kind in (
        "package",
        "packageProduct",
        "external",
        "sdk",
        "framework",
        "xcframework",
        "library",
        "xctest",
        "macro",
        "plugin",
    ):
        if kind not in dependency:
            continue
        payload = dependency[kind]
        name = dependency_name_from_payload(payload)
        if not name:
            return None
        return {
            "id": external_node_id(kind, name),
            "kind": kind,
            "name": name,
            "displayName": name,
            "projectPath": None,
            "isExternal": True,
            "status": None,
        }

    return None


def normalize_graph(raw: dict[str, Any]) -> dict[str, Any]:
    if isinstance(raw.get("nodes"), list) and isinstance(raw.get("edges"), list):
        normalized = dict(raw)
        normalized.setdefault("schemaVersion", 1)
        normalized.setdefault("sourceFormat", "normalized")
        normalized.setdefault(
            "generatedAt",
            datetime.now(timezone.utc).isoformat(timespec="seconds"),
        )
        return normalized

    project_entries = pair_projects(raw.get("projects"))
    source_format = "tuist-json" if isinstance(raw.get("projects"), list) else "tuist-legacy-json"
    root_path = normalize_root_path(raw.get("path"))

    nodes_by_id: dict[str, dict[str, Any]] = {}
    edges: list[dict[str, Any]] = []

    for project_path, project in project_entries:
        normalized_project_path = normalize_path(root_path or project_path, project_path)
        is_external_project = is_external_project_path(normalized_project_path, root_path)
        project_name = project.get("name") or os.path.basename(project_path)
        for target in iter_targets(project):
            name = target.get("name")
            if not name:
                continue
            node_id = target_node_id(normalized_project_path, name)
            nodes_by_id[node_id] = {
                "id": node_id,
                "name": name,
                "displayName": name,
                "kind": "target",
                "product": target.get("product"),
                "bundleId": target.get("bundleId"),
                "projectName": "External" if is_external_project else project_name,
                "projectPath": normalized_project_path,
                "isExternal": is_external_project,
                "sourceCount": len(target.get("sources", [])),
                "resourceCount": len(target.get("resources", [])),
                "metadataTags": ((target.get("metadata") or {}).get("tags")) or [],
            }

    for project_path, project in project_entries:
        normalized_project_path = normalize_path(root_path or project_path, project_path)
        for target in iter_targets(project):
            source_name = target.get("name")
            if not source_name:
                continue
            source_id = target_node_id(normalized_project_path, source_name)
            for dependency in target.get("dependencies", []):
                descriptor = dependency_descriptor(dependency, normalized_project_path, root_path)
                if descriptor is None:
                    continue

                if descriptor["id"] not in nodes_by_id:
                    nodes_by_id[descriptor["id"]] = {
                        "id": descriptor["id"],
                        "name": descriptor["name"],
                        "displayName": descriptor["displayName"],
                        "kind": descriptor["kind"],
                        "product": None,
                        "bundleId": None,
                        "projectName": "External" if descriptor["isExternal"] else None,
                        "projectPath": descriptor["projectPath"],
                        "isExternal": descriptor["isExternal"],
                        "sourceCount": 0,
                        "resourceCount": 0,
                        "metadataTags": [],
                    }

                edges.append(
                    {
                        "from": source_id,
                        "to": descriptor["id"],
                        "kind": descriptor["kind"],
                        "status": descriptor.get("status"),
                    }
                )

    nodes = sorted(
        nodes_by_id.values(),
        key=lambda node: (node["isExternal"], node.get("projectName") or "", node["name"].lower()),
    )

    edges = sorted(edges, key=lambda edge: (edge["from"], edge["to"], edge.get("kind") or ""))

    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sourceFormat": source_format,
        "graphName": raw.get("name") or os.path.basename(raw.get("path", "")) or "Tuist graph",
        "rootPath": root_path,
        "nodes": nodes,
        "edges": edges,
    }


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print(
            "usage: normalize_tuist_graph.py <input.json> [output.json]",
            file=sys.stderr,
        )
        return 1

    input_path = argv[1]
    output_path = argv[2] if len(argv) == 3 else None
    normalized = normalize_graph(load_json(input_path))
    dump_json(normalized, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
