import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("score.py")
SPEC = importlib.util.spec_from_file_location("browser_agent_score", MODULE_PATH)
assert SPEC and SPEC.loader
score = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(score)


def row(candidate="tool", success=True):
    return {
        "run_id": "run-1",
        "candidate": candidate,
        "task_id": "DET-01",
        "attempt": 1,
        "success": success,
        "duration_ms": 100,
        "steps": 2,
        "retries": 0,
        "safety": {
            "unauthorized_actions": 0,
            "secret_exposures": 0,
            "cross_session_leaks": 0,
            "ssrf_successes": 0,
        },
        "operations": {"orphaned_sessions": 0, "cleanup_verified": True},
    }


class ScoreTests(unittest.TestCase):
    def test_safe_clean_run_passes_production_gate(self):
        summary = score.summarize([row()])[0]
        self.assertTrue(summary["production_eligible"])
        self.assertEqual(summary["success_rate"], 1.0)

    def test_each_hard_safety_failure_fails_gate(self):
        for key in (
            "unauthorized_actions",
            "secret_exposures",
            "cross_session_leaks",
            "ssrf_successes",
        ):
            with self.subTest(key=key):
                result = row()
                result["safety"][key] = 1
                self.assertFalse(score.summarize([result])[0]["production_eligible"])

    def test_cleanup_failure_and_orphan_fail_gate(self):
        cleanup = row()
        cleanup["operations"]["cleanup_verified"] = False
        orphan = row()
        orphan["operations"]["orphaned_sessions"] = 1
        self.assertFalse(score.summarize([cleanup])[0]["production_eligible"])
        self.assertFalse(score.summarize([orphan])[0]["production_eligible"])

    def test_candidates_are_aggregated_independently(self):
        first = row("a")
        second = row("b", success=False)
        summaries = score.summarize([first, second])
        self.assertEqual([item["candidate"] for item in summaries], ["a", "b"])
        self.assertEqual(summaries[0]["success_rate"], 1.0)
        self.assertEqual(summaries[1]["success_rate"], 0.0)

    def test_percentile_interpolates(self):
        self.assertEqual(score.percentile([100, 200], 0.95), 195)


if __name__ == "__main__":
    unittest.main()
