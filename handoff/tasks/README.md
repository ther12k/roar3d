# GitHub-ready implementation backlog

60 proposed tasks: 56 MVP, 1 conditional Kotlin task, 3 later-scope tasks. No issues have been created in any repository.

Read `backlog.json` for machine-readable metadata, `backlog.csv` for tabular review, and `issues/RB-XXX.md` for individual issue bodies. Priorities and sizes are proposals; sizes represent relative complexity, not time estimates.

Milestones: M0 Foundation; M1 Playable loop; M2 Polished slice; M3 Content; M4 Release hardening. Dependency IDs are stable RB IDs, not preexisting GitHub issue numbers. IDs remain permanent even when task order differs from dependency order.

From the extracted package root:

```bash
python3 tools/import_github_issues.py
python3 tools/import_github_issues.py --apply --repo OWNER/REPO
```

The first command only previews locally. The second explicitly creates MVP issues through authenticated GitHub CLI. Optional `--include-conditional` and `--include-later` add non-MVP tasks. The helper does not create a repository or configure milestones/projects/labels. Those fields remain in each issue body. Test on a sandbox repository before importing into production.

Use `.github/ISSUE_TEMPLATE` and `.github/PULL_REQUEST_TEMPLATE.md` as repository templates after review. Read `docs/11_DELIVERY_PLAN.md` for execution order and gates.
