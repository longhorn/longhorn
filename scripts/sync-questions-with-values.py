#!/usr/bin/env python3
"""
Sync chart/questions.yaml default values and descriptions with chart/values.yaml.

This script reads values.yaml (the source of truth), extracts all key paths with
their default values and descriptions (from helm-doc style comments), then updates
questions.yaml entries that have drifted.

Usage:
    python3 scripts/sync-questions-with-values.py [--check]

Options:
    --check   Only check for differences, exit with code 1 if out of sync.
              Without this flag, questions.yaml is updated in place.
"""

import re
import sys
import yaml


def parse_values_yaml(filepath):
    """Parse values.yaml and return a dict of dotted-key-path -> {value, description}."""
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {filepath} not found.", file=sys.stderr)
        sys.exit(1)

    lines = content.splitlines(True)
    data = yaml.safe_load(content)

    # Build a map of dotted paths to their values from the parsed YAML
    values = {}
    _flatten(data, "", values)

    # Build a map of dotted paths to their descriptions from comments
    descriptions = _extract_descriptions(lines)

    result = {}
    for key, val in values.items():
        result[key] = {
            "value": val,
            "description": descriptions.get(key, None),
        }
    return result


def _flatten(data, prefix, result):
    """Recursively flatten a nested dict into dotted key paths."""
    if isinstance(data, dict):
        for k, v in data.items():
            new_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                _flatten(v, new_key, result)
            else:
                result[new_key] = v
    # Lists and scalars are leaf values, already captured by the caller


def _extract_descriptions(lines):
    """Extract helm-doc style descriptions (# -- ...) mapped to the next YAML key."""
    descriptions = {}
    indent_stack = []  # stack of (indent_level, key_name)
    pending_description = None

    for line in lines:
        stripped = line.rstrip()

        # Check for helm-doc comment: # -- description text
        match = re.match(r'^(\s*)# -- (.+)$', stripped)
        if match:
            indent = len(match.group(1))
            desc_text = match.group(2).strip()
            pending_description = (indent, desc_text)
            continue

        # Check for continuation comment lines (part of multi-line description)
        if pending_description is not None:
            cont_match = re.match(r'^(\s*)# (.+)$', stripped)
            if cont_match and not re.match(r'^(\s*)# --', stripped):
                indent = len(cont_match.group(1))
                if indent == pending_description[0]:
                    pending_description = (
                        pending_description[0],
                        pending_description[1] + " " + cont_match.group(2).strip(),
                    )
                    continue

        # Check for a YAML key line
        key_match = re.match(r'^(\s*)(\w[\w.-]*):\s*(.*?)$', stripped)
        if key_match:
            indent = len(key_match.group(1))
            key_name = key_match.group(2)

            # Update indent stack
            while indent_stack and indent_stack[-1][0] >= indent:
                indent_stack.pop()

            indent_stack.append((indent, key_name))

            # Build full dotted path
            full_path = ".".join(item[1] for item in indent_stack)

            if pending_description is not None:
                desc_indent, desc_text = pending_description
                if desc_indent == indent:
                    descriptions[full_path] = desc_text
                pending_description = None
            else:
                pending_description = None
        elif stripped and not stripped.lstrip().startswith('#'):
            # Non-comment, non-key line resets pending description
            pending_description = None

    return descriptions


def normalize_value(val):
    """Normalize a value for comparison."""
    if val is None:
        return None
    if isinstance(val, bool):
        return str(val).lower()
    return str(val)


def normalize_description(desc):
    """Normalize description text for comparison."""
    if desc is None:
        return None
    # Collapse whitespace
    return " ".join(desc.split())


def update_questions(questions_data, values_info, check_only=False):
    """Update questions.yaml data with values from values.yaml.

    Returns a list of changes made (or that would be made in check mode).
    """
    changes = []

    def process_items(items):
        if not items:
            return
        for item in items:
            variable = item.get("variable")
            if variable and variable in values_info:
                info = values_info[variable]
                val_default = info["value"]
                val_desc = info["description"]

                # Compare and update default value
                q_default = item.get("default")
                if val_default is not None:
                    normalized_q = normalize_value(q_default)
                    normalized_v = normalize_value(val_default)
                    if normalized_q != normalized_v:
                        changes.append(
                            f"default: {variable}: "
                            f"'{q_default}' -> '{val_default}'"
                        )
                        if not check_only:
                            item["default"] = val_default

                # Compare and update description
                if val_desc is not None:
                    q_desc = item.get("description", "")
                    if normalize_description(q_desc) != normalize_description(val_desc):
                        changes.append(
                            f"description: {variable}: "
                            f"'{q_desc}' -> '{val_desc}'"
                        )
                        if not check_only:
                            item["description"] = val_desc

            # Recurse into subquestions
            process_items(item.get("subquestions"))

    process_items(questions_data.get("questions", []))
    return changes


def main():
    check_only = "--check" in sys.argv

    values_info = parse_values_yaml("chart/values.yaml")
    try:
        with open("chart/questions.yaml", "r") as f:
            questions_data = yaml.safe_load(f)
    except FileNotFoundError:
        print("Error: chart/questions.yaml not found.", file=sys.stderr)
        sys.exit(1)

    changes = update_questions(questions_data, values_info, check_only=check_only)

    if changes:
        print(f"Found {len(changes)} difference(s):")
        for change in changes:
            print(f"  - {change}")

        if check_only:
            print("\nquestions.yaml is out of sync with values.yaml.")
            sys.exit(1)
        else:
            with open("chart/questions.yaml", "w") as f:
                yaml.dump(
                    questions_data,
                    f,
                    default_flow_style=False,
                    allow_unicode=True,
                    width=1000,
                    sort_keys=False,
                )
            print("\nquestions.yaml has been updated.")
    else:
        print("questions.yaml is in sync with values.yaml.")


if __name__ == "__main__":
    main()
