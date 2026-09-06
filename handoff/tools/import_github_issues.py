#!/usr/bin/env python3
"""Preview locally by default; create issues only with explicit --apply --repo.

Requires authenticated GitHub CLI only for --apply. Does not configure repositories,
labels, milestones, projects or releases. No secrets are read into application logs.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def load_issues(root: Path = ROOT) -> list[dict]:
    data = json.loads((root / 'tasks/backlog.json').read_text(encoding='utf-8'))
    issues = data['issues']
    if len({i['id'] for i in issues}) != len(issues):
        raise ValueError('Duplicate backlog IDs.')
    for issue in issues:
        path = (root / issue['body_path']).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError(f"Invalid issue body path for {issue['id']}")
    return issues


def select_issues(issues: list[dict], conditional: bool, later: bool) -> list[dict]:
    allowed = {'mvp'}
    if conditional:
        allowed.add('conditional')
    if later:
        allowed.add('later')
    selected = [i for i in issues if i['scope'] in allowed]
    # Stable topological order, so dependency issues are normally created first.
    by_id = {i['id']: i for i in selected}
    result: list[dict] = []
    done: set[str] = set()
    while len(result) < len(selected):
        ready = [i for i in selected if i['id'] not in done and
                 all(d in done or d not in by_id for d in i['depends_on'])]
        if not ready:
            raise ValueError('Dependency cycle in selected issues.')
        for issue in ready:
            result.append(issue)
            done.add(issue['id'])
    return result


def run_gh(args: list[str]) -> str:
    completed = subprocess.run(['gh', *args], text=True, capture_output=True,
                               check=False, timeout=90)
    if completed.returncode != 0:
        # Do not dump arbitrary CLI output that might contain sensitive context.
        raise RuntimeError(f'GitHub CLI failed (exit {completed.returncode}); '
                           'check gh auth status and repository permissions. '
                           'Rerun after inspecting repository state.')
    return completed.stdout.strip()


def existing_ids(repo: str) -> dict[str, int]:
    found: dict[str, int] = {}
    page = 1
    while True:
        payload = run_gh(['api', f'repos/{repo}/issues?state=all&per_page=100&page={page}'])
        items = json.loads(payload)
        if not isinstance(items, list):
            raise RuntimeError('Unexpected GitHub response; no issues will be created.')
        for issue in items:
            if 'pull_request' in issue:
                continue
            match = re.match(r'^\[(RB-\d{3})\]', issue.get('title', ''))
            if match:
                found[match.group(1)] = int(issue['number'])
        if len(items) < 100:
            return found
        page += 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Explicitly create remote issues.')
    parser.add_argument('--repo', help='Target OWNER/REPO; required with --apply.')
    parser.add_argument('--include-conditional', action='store_true')
    parser.add_argument('--include-later', action='store_true')
    args = parser.parse_args(argv)
    try:
        issues = select_issues(load_issues(), args.include_conditional, args.include_later)
        print(f'{len(issues)} selected tasks. ' + ('APPLY requested.' if args.apply else 'LOCAL PREVIEW ONLY.'))
        for issue in issues:
            print(f"{issue['id']} | {issue['milestone']} | {issue['priority']} | {issue['title']}")
        if not args.apply:
            print('\nNo network access and no remote changes performed.')
            print('To create issues after review: --apply --repo OWNER/REPO')
            return 0
        if not args.repo or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
            raise ValueError('--apply requires a valid OWNER/REPO (not a URL).')
        if shutil.which('gh') is None:
            raise RuntimeError('GitHub CLI is not installed. Install/authenticate gh first.')
        existing = existing_ids(args.repo)
        for issue in issues:
            if issue['id'] in existing:
                print(f"SKIP {issue['id']}: existing issue #{existing[issue['id']]}")
                continue
            body_file = str((ROOT / issue['body_path']).resolve())
            url = run_gh(['issue', 'create', '--repo', args.repo,
                          '--title', issue['title'], '--body-file', body_file])
            print(f"CREATED {issue['id']}: {url}")
        print('Finished. Scope/milestone/dependencies are in bodies; no boards/labels configured.')
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
