#!/usr/bin/env python3
"""Validate planning artifacts, not playable scenes or device behavior.

Uses standard library semantic checks; additionally validates JSON Schema when
jsonschema is installed. Intentionally does not require target .tscn files:
all catalog entries in this planning package are explicitly design_only.
"""
from __future__ import annotations
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def validate(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    def require(ok: bool, message: str) -> None:
        if not ok:
            errors.append(message)
    backlog = json.loads((root / 'tasks/backlog.json').read_text())
    issues = backlog['issues']
    ids = {i['id'] for i in issues}
    require(len(issues) == 60 and len(ids) == 60, 'Expected 60 unique task IDs.')
    require(sum(i['scope']=='mvp' for i in issues)==56, 'Expected 56 MVP tasks.')
    require(sum(i['scope']=='conditional' for i in issues)==1, 'Expected one conditional task.')
    require(sum(i['scope']=='later' for i in issues)==3, 'Expected three later tasks.')
    for issue in issues:
        require(all(d in ids for d in issue['depends_on']), f"Unknown dependency: {issue['id']}")
        require(issue['id'] not in issue['depends_on'], f"Self dependency: {issue['id']}")
        require(len(issue['acceptance_criteria']) >= 3, f"Missing acceptance: {issue['id']}")
        for rel in [issue['body_path'], *issue['references']]:
            p = (root / rel).resolve()
            require(p.is_relative_to(root.resolve()) and p.is_file(), f'Missing/unsafe path: {rel}')
    graph = {i['id']: i['depends_on'] for i in issues}
    visited: set[str] = set()
    stack: set[str] = set()
    def visit(node: str) -> None:
        if node in stack:
            errors.append(f'Dependency cycle at {node}'); return
        if node in visited:
            return
        stack.add(node)
        for dep in graph.get(node, []):
            visit(dep)
        stack.remove(node); visited.add(node)
    for rid in graph:
        visit(rid)
    catalog = json.loads((root / 'content/level_catalog.json').read_text())
    levels = catalog['levels']
    require(len(levels)==12, 'Expected 12 design briefs.')
    require(len({l['id'] for l in levels})==12, 'Duplicate level IDs.')
    require(sorted(l['order'] for l in levels)==list(range(1,13)), 'Invalid global level order.')
    mechanics={'turf','cup','rail','ramp','void','moving_gate','portal','bounce_pad'}
    for world,prefix in [('cloud_cliffs','CC'),('portal_peaks','PP')]:
        group = [l for l in levels if l['world_id']==world]
        require(len(group)==6, f'{world} needs 6 levels.')
        require(sorted(l['world_index'] for l in group)==list(range(1,7)), f'{world} index mismatch.')
        for l in group:
            require(l['id']==f"{prefix}{l['world_index']:02d}", f"Wrong ID/world mapping: {l['id']}")
    for l in levels:
        require(l['scene_path']==f"res://scenes/levels/{l['id']}.tscn", f"Path mismatch: {l['id']}")
        require(l['status']=='design_only', f"Unproven runtime validation: {l['id']}")
        require(l['max_strokes']==12 and l['max_strokes']>=l['par']+2, f"Score metadata: {l['id']}")
        require(set(l['mechanics']) <= mechanics, f"Unknown mechanic: {l['id']}")
    try:
        from jsonschema import Draft202012Validator
        schema=json.loads((root / 'content/schemas/level_catalog.schema.json').read_text())
        Draft202012Validator.check_schema(schema)
        errors.extend('JSON Schema: '+e.message for e in Draft202012Validator(schema).iter_errors(catalog))
    except ImportError:
        print('NOTE: jsonschema unavailable; semantic checks ran, formal schema validation skipped.')
    require(len(list((root/'design/references').glob('*.png')))==7, 'Expected 7 reference PNGs.')
    for required in ['START_HERE.md','AI_AGENT_HANDOFF.md','docs/13_SOURCES.md','design/design_tokens.json']:
        require((root/required).is_file(), f'Missing {required}')
    return errors


if __name__=='__main__':
    try:
        failures=validate()
        if failures:
            print('\n'.join('FAIL: '+x for x in failures)); sys.exit(1)
        print('PASS: 60 tasks, dependency graph, 12 design briefs, data contracts, 7 PNGs, and document references.')
        print('This does NOT test Godot parsing, playable scenes, microphone hardware, Android builds, or performance.')
    except (OSError, ValueError, KeyError) as exc:
        print(f'FAIL: {exc}'); sys.exit(1)
