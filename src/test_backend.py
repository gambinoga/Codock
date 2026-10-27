import importlib.util
import contextlib
import io
from unittest import mock
import json
import os
import subprocess
from pathlib import Path
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


backend, hook, installer = load("backend"), load("hook"), load("install_hooks")
local_installer = load("install_local")


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.data = self.root / "data"
        self.data.mkdir()
        self.home = self.root / "codex"
        self.home.mkdir()
        names = ["dss14", "dss14-b", "dss14-c", "dss14-d"]
        self.configuration = {"projects": [{"id": name, "name": name.upper(), "codexID": "codex-" + name,
                                           "roots": [str(Path.home() / "devenv" / name / "dip")], "palette": index}
                                          for index, name in enumerate(names)]}
        (self.data / "configuration.json").write_text(json.dumps(self.configuration))
        state = {"thread-titles": {"titles": {"a": "Task A", "b": "Task B"}}, "local-projects": {
            p["codexID"]: {"name": p["id"], "rootPaths": p["roots"]} for p in self.configuration["projects"]}}
        (self.home / ".codex-global-state.json").write_text(json.dumps(state))
        c = sqlite3.connect(self.home / "state_5.sqlite")
        c.execute("create table threads(id text,cwd text,name text,project_id text,source text,archived int,updated_at int)")
        roots = {p["id"]: p["roots"][0] for p in self.configuration["projects"]}
        c.executemany("insert into threads values(?,?,?,?,?,?,?)", [
            ("a", roots["dss14"], None, None, "vscode", 0, 3),
            ("b", roots["dss14-b"], None, None, "vscode", 0, 2),
            ("child", roots["dss14"], None, None, '{"subagent":{}}', 0, 1)])
        c.commit(); c.close()
        c = sqlite3.connect(self.home / "thread_history_1.sqlite")
        c.execute("create table thread_turns(thread_id text,turn_id text,rollout_ordinal int,status text,started_at int,completed_at int)")
        c.executemany("insert into thread_turns values(?,?,?,?,?,?)", [
            ("a", "old", 1, "completed", 1, 2), ("a", "new", 2, "inProgress", 3, None),
            ("b", "b1", 1, "completed", 1, 2), ("child", "x", 1, "inProgress", 1, None)])
        c.commit(); c.close()
        (self.home / "thread-writer-locks").mkdir()
        (self.home / "thread-writer-locks" / "a.lock").touch()

    def tearDown(self):
        self.temp.cleanup()

    @unittest.skipUnless(os.environ.get("DOCK_READER_BINARY"), "Standalone reader tested in release CI")
    def test_standalone_reader_matches_source(self):
        output = subprocess.check_output([os.environ["DOCK_READER_BINARY"], "--home", str(self.home), "--data", str(self.data)], text=True)
        actual = json.loads(output)
        expected = backend.snapshot(self.home, self.data)
        self.assertTrue(actual["connected"])
        self.assertEqual(actual["tasks"], expected["tasks"])
        self.assertEqual(actual["availableProjects"], expected["availableProjects"])

    def test_latest_turn_exact_project_and_no_subagents(self):
        result = backend.snapshot(self.home, self.data)
        self.assertEqual([(t["id"], t["project"], t["turn"]) for t in result["tasks"]],
                         [("a", "dss14", "new"), ("b", "dss14-b", "b1")])
        self.assertEqual(result["tasks"][0]["title"], "Task A")

    def test_status_timestamps_preserve_start_finish_and_question_time(self):
        rows = backend.snapshot(self.home, self.data)["tasks"]
        self.assertEqual((rows[0]["stateChanged"], rows[1]["stateChanged"]), (3, 2))
        event = {"session_id": "a", "turn_id": "new", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}
        with mock.patch.object(hook.time, "time", return_value=1234):
            hook.observe(event, self.data, self.home)
        waiting = backend.snapshot(self.home, self.data)["tasks"][0]
        self.assertEqual((waiting["started"], waiting["stateChanged"]), (3, 1234))

    def test_parallel_tool_does_not_restart_question_age(self):
        event = {"session_id": "a", "turn_id": "new", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}
        with mock.patch.object(hook.time, "time", return_value=1234):
            hook.observe(event, self.data, self.home)
        with mock.patch.object(hook.time, "time", return_value=1300):
            hook.observe(dict(event, tool_name="Bash", hook_event_name="PostToolUse"), self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["stateChanged"], 1234)
        hook.observe(dict(event, hook_event_name="PostToolUse"), self.data, self.home)
        with mock.patch.object(hook.time, "time", return_value=1400):
            hook.observe(event, self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["stateChanged"], 1400)

    def test_project_configuration_does_not_truncate_after_four(self):
        configuration = {"projects": [{"id": str(i), "name": "P" + str(i), "roots": ["/tmp/p" + str(i)]} for i in range(25)]}
        projects = backend.projects_from({}, configuration)
        self.assertEqual(len(projects), 25)
        self.assertEqual(backend.project_for({"id": "last", "cwd": "/tmp/p24/src"}, {}, projects), "24")

    def test_archived_chat_reported_explicitly_and_excluded_from_tasks(self):
        with sqlite3.connect(self.home / "state_5.sqlite") as db:
            db.execute("UPDATE threads SET archived=1 WHERE id='b'")
        result = backend.snapshot(self.home, self.data)
        self.assertEqual(result["archivedIDs"], ["b"])
        self.assertNotIn("b", [t["id"] for t in result["tasks"]])

    def test_temporary_database_error_recovers_in_same_refresh(self):
        good = backend.snapshot(self.home, self.data)
        output = io.StringIO()
        with mock.patch.object(backend, "snapshot", side_effect=[sqlite3.OperationalError("unable to open database file"), good]) as read, mock.patch.object(backend.sys, "argv", ["backend.py", "--home", str(self.home), "--data", str(self.data)]), mock.patch.object(backend.time, "sleep"), contextlib.redirect_stdout(output):
            backend.main()
        self.assertEqual(read.call_count, 2)
        self.assertTrue(json.loads(output.getvalue())["connected"])
        status = json.loads((self.data / "reader-status.json").read_text())
        self.assertTrue(status["connected"])
        self.assertIsNone(status["error"])

    def test_persistent_database_error_stops_after_three_attempts(self):
        output = io.StringIO()
        with mock.patch.object(backend, "snapshot", side_effect=sqlite3.OperationalError("unable to open database file")) as read, mock.patch.object(backend.sys, "argv", ["backend.py", "--home", str(self.home), "--data", str(self.data)]), mock.patch.object(backend.time, "sleep"), contextlib.redirect_stdout(output):
            backend.main()
        self.assertEqual(read.call_count, 3)
        self.assertFalse(json.loads(output.getvalue())["connected"])

    def test_permission_review_keeps_loading(self):
        event = {"session_id": "a", "turn_id": "new", "tool_use_id": "call1", "tool_name": "Bash", "hook_event_name": "PermissionRequest"}
        hook.observe(event, self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "inProgress")
        hook.observe(dict(event, hook_event_name="PostToolUse"), self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "inProgress")

    def test_legacy_approvals_do_not_hide_loading(self):
        (self.data / "waiting.json").write_text(json.dumps({"a": {"turn": "new", "pending": {"Bash": "approval"}}}))
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "inProgress")

    def test_explicit_question_waits_until_answer(self):
        event = {"session_id": "a", "turn_id": "new", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}
        hook.observe(event, self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "waiting")
        hook.observe(dict(event, hook_event_name="PostToolUse", tool_use_id="call1"), self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "inProgress")

    def test_async_question_keeps_loading(self):
        hook.observe({"session_id": "a", "turn_id": "new", "tool_name": "request_user_input_async", "hook_event_name": "PreToolUse"}, self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "inProgress")

    def test_old_pending_does_not_block_new_turn(self):
        hook.observe({"session_id": "a", "turn_id": "old", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}, self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "inProgress")

    def test_stale_inprogress_not_reported_running(self):
        (self.home / "thread-writer-locks" / "a.lock").unlink()
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "notLoaded")

    def test_no_false_prefix_match_and_explicit_membership(self):
        project = backend.projects_from({}, self.configuration)
        thread = {"id": "a", "cwd": str(Path.home() / "devenv/dss14-b/dip")}
        self.assertEqual(backend.project_for(thread, {}, project), "dss14-b")
        thread["cwd"] = "/tmp/worktree"
        state = {"thread-project-assignments": {"a": "codex-dss14-c"}}
        self.assertEqual(backend.project_for(thread, state, project), "dss14-c")

    def test_configurable_alias_does_not_change_task_identity(self):
        self.configuration["projects"][0]["name"] = "NEWNAME"
        (self.data / "configuration.json").write_text(json.dumps(self.configuration))
        result = backend.snapshot(self.home, self.data)
        self.assertEqual(result["tasks"][0]["project"], "dss14")
        self.assertEqual(len(result["availableProjects"]), 4)

    def test_unselected_explicit_project_does_not_leak_through_roots(self):
        projects = backend.projects_from({}, self.configuration)
        thread = {"id": "a", "cwd": self.configuration["projects"][0]["roots"][0], "project_id": "another-project"}
        self.assertIsNone(backend.project_for(thread, {}, projects))

    def test_longest_manual_folder_wins(self):
        projects = [{"id": None, "name": "parent", "roots": ["/tmp/work"]}, {"id": None, "name": "child", "roots": ["/tmp/work/child"]}]
        self.assertEqual(backend.project_for({"id": "x", "cwd": "/tmp/work/child/src"}, {}, projects), "child")
        self.assertIsNone(backend.project_for({"id": "x", "cwd": "/tmp/work-other"}, {}, projects))

    def test_manual_folder_can_scope_an_explicit_codex_project(self):
        projects = [{"id": None, "name": "manual", "roots": ["/tmp/work"]}]
        self.assertEqual(backend.project_for({"id": "x", "cwd": "/tmp/work/src", "project_id": "codex-one"}, {}, projects), "manual")

    def test_no_personal_defaults_for_new_installation(self):
        (self.data / "configuration.json").unlink()
        result = backend.snapshot(self.home, self.data)
        self.assertEqual(result["tasks"], [])
        self.assertEqual(len(result["availableProjects"]), 4)

    def test_metadata_matching_does_not_touch_project_folders(self):
        projects = [{"id": None, "name": "manual", "roots": ["/Users/test/Documents/work"]}]
        with mock.patch.object(backend.os.path, "realpath", side_effect=AssertionError("must not traverse folders")):
            self.assertEqual(backend.project_for({"id": "x", "cwd": "/Users/test/Documents/work/../work/src"}, {}, projects), "manual")
            self.assertIsNone(backend.project_for({"id": "other", "cwd": "/Users/test/Desktop/unrelated"}, {}, projects))

    def test_migration_preserves_existing_data_and_is_repeatable(self):
        support = self.root / "support"
        (self.data / "state.json").write_text('{"notices":["old"]}')
        local_installer.migrate_data(self.data, support)
        self.assertEqual((support / "state.json").read_text(), '{"notices":["old"]}')
        (support / "state.json").write_text('{"notices":["new"]}')
        local_installer.migrate_data(self.data, support)
        self.assertEqual((support / "state.json").read_text(), '{"notices":["new"]}')
        self.assertEqual((self.data / "state.json").read_text(), '{"notices":["old"]}')
        self.assertEqual(json.loads((self.data / "data-redirect.json").read_text())["data"], str(support))

    def test_legacy_hook_redirects_to_application_support(self):
        support = self.root / "Library/Application Support/Notifs"
        local_installer.migrate_data(self.data, support)
        with mock.patch.object(hook.Path, "home", return_value=self.root):
            hook.observe({"session_id": "a", "turn_id": "new", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}, self.data, self.home)
        self.assertEqual(json.loads((support / "waiting.json").read_text())["a"]["pending"], {"request_user_input": "input"})
        self.assertFalse((self.data / "waiting.json").exists())

    def test_hook_uses_selected_codex_home(self):
        configuration = dict(self.configuration, codexHome=str(self.home))
        (self.data / "configuration.json").write_text(json.dumps(configuration))
        hook.observe({"session_id": "a", "turn_id": "new", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}, self.data)
        self.assertEqual(json.loads((self.data / "waiting.json").read_text())["a"]["pending"], {"request_user_input": "input"})

    def test_hook_merge_preserves_other_hooks_and_is_idempotent(self):
        source = {"hooks": {"PermissionRequest": [{"hooks": [{"type": "command", "command": "existing"}]}]}}
        result = installer.merged_hooks(source, self.root)
        result = installer.merged_hooks(result, self.root)
        self.assertEqual(len(result["hooks"]["PermissionRequest"]), 2)
        self.assertEqual(result["hooks"]["PermissionRequest"][0]["hooks"][0]["command"], "existing")

    def test_hook_does_not_store_sensitive_inputs(self):
        hook.observe({"session_id": "a", "turn_id": "new", "hook_event_name": "PermissionRequest", "tool_input": {"secret": "never-copy"}}, self.data, self.home)
        self.assertNotIn("never-copy", (self.data / "waiting.json").read_text())

    def test_child_turn_cannot_erase_parent_waiting(self):
        hook.observe({"session_id": "a", "turn_id": "new", "tool_name": "request_user_input", "hook_event_name": "PreToolUse"}, self.data, self.home)
        hook.observe({"session_id": "a", "turn_id": "child-turn", "hook_event_name": "PostToolUse"}, self.data, self.home)
        self.assertEqual(backend.snapshot(self.home, self.data)["tasks"][0]["status"], "waiting")


if __name__ == "__main__":
    unittest.main()
