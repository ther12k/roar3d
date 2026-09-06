# Local tools

Requires Python 3.10+. Package validator and tests run locally without contacting GitHub. Optional `jsonschema` enables formal JSON Schema validation; semantic checks still run without it. Tests are Python reference-contract/tooling tests, not Godot engine tests.

```bash
python3 tools/validate_package.py
python3 tools/test_contracts.py
python3 tools/test_tooling.py
python3 tools/import_github_issues.py
```

For reviewed remote issue creation only:

```bash
python3 tools/import_github_issues.py --apply --repo OWNER/REPO
```

The importer requires GitHub CLI and a repository you can write to. The default preview does not need GitHub CLI. Apply fetches existing issue titles, skips stable RB IDs, and creates missing issues in dependency order. It does not modify existing issues, create a repository, or set up project/milestone/label metadata. Re-run after checking partial failures; stable IDs are used to reduce duplicate reruns. Concurrent importers are not supported.

Remote import was not exercised in this delivery. Test in a sandbox repository before real use. Never put a token in command arguments or committed files; authenticate GitHub CLI through its supported mechanism.
