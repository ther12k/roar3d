#!/usr/bin/env python3
"""Tests tooling locally; does not call GitHub."""
from contextlib import redirect_stdout
import io
import unittest
from unittest.mock import patch
import import_github_issues as importer

class ToolingTests(unittest.TestCase):
    def test_mvp_selection(self):
        self.assertEqual(len(importer.select_issues(importer.load_issues(),False,False)),56)
    def test_all_selection(self):
        self.assertEqual(len(importer.select_issues(importer.load_issues(),True,True)),60)
    def test_conditional_selection(self):
        self.assertEqual(len(importer.select_issues(importer.load_issues(),True,False)),57)
    def test_dependency_order(self):
        selected=importer.select_issues(importer.load_issues(),True,True)
        positions={x['id']:i for i,x in enumerate(selected)}
        for item in selected:
            for dep in item['depends_on']:
                self.assertLess(positions[dep],positions[item['id']])
    def test_preview_no_remote_commands(self):
        with patch.object(importer,'run_gh',side_effect=AssertionError('Network prohibited')):
            with redirect_stdout(io.StringIO()):
                self.assertEqual(importer.main([]),0)
    def test_existing_id_parsing_excludes_pull_requests(self):
        payload='[{"title":"[RB-001] Existing","number":4},{"title":"[RB-002] PR","number":5,"pull_request":{}}]'
        with patch.object(importer,'run_gh',return_value=payload):
            self.assertEqual(importer.existing_ids('owner/repo'),{'RB-001':4})

if __name__=='__main__': unittest.main(verbosity=2)
