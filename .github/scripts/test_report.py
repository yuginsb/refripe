#!/usr/bin/env python3
"""Export screenshots and a plain-text test report from an .xcresult bundle.

Usage: test_report.py <TestResults.xcresult> <test.log> <out_dir>
Writes:
  <out_dir>/screens/*.png   screenshots named after their XCTAttachment name
  <out_dir>/summary.txt     counts + every test case with its result
  <out_dir>/failures.txt    failing tests with their messages (empty when all passed)
Never fails the job: missing pieces are reported in summary.txt.
"""
import json
import os
import re
import shutil
import subprocess
import sys

xcresult, log_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
screens = os.path.join(out_dir, "screens")
os.makedirs(screens, exist_ok=True)
notes = []


def run(*args):
    return subprocess.run(["xcrun", "xcresulttool", *args], capture_output=True, text=True)


def safe(name):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or "attachment"


# ---------------------------------------------------------------- screenshots
def export_attachments_new():
    tmp = os.path.join(out_dir, "_attachments")
    shutil.rmtree(tmp, ignore_errors=True)
    r = run("export", "attachments", "--path", xcresult, "--output-path", tmp)
    if r.returncode != 0:
        notes.append("export attachments failed: " + (r.stderr or r.stdout).strip()[:500])
        return False
    manifest_path = os.path.join(tmp, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else []
    count = 0
    for test in manifest:
        for a in test.get("attachments", []):
            src = os.path.join(tmp, a["exportedFileName"])
            human = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            base, ext = os.path.splitext(human)
            # "01-discover-swipe_0_1A2B…" → "01-discover-swipe"
            base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", base)
            dst = os.path.join(screens, safe(base) + (ext or ".png"))
            n = 2
            while os.path.exists(dst):
                dst = os.path.join(screens, f"{safe(base)}-{n}{ext or '.png'}")
                n += 1
            shutil.copy(src, dst)
            count += 1
    shutil.rmtree(tmp, ignore_errors=True)
    notes.append(f"exported {count} attachment(s) with `xcresulttool export attachments`")
    return True


def legacy_get(obj_id=None):
    for extra in (["--legacy"], []):
        args = ["get", *extra, "--format", "json", "--path", xcresult]
        if obj_id:
            args += ["--id", obj_id]
        r = run(*args)
        if r.returncode == 0:
            return json.loads(r.stdout), extra
    return None, []


def walk(node, key):
    """Yield every dict under `node` that has `key`."""
    if isinstance(node, dict):
        if key in node:
            yield node
        for v in node.values():
            yield from walk(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v, key)


def export_attachments_legacy():
    root, extra = legacy_get()
    if root is None:
        notes.append("legacy xcresulttool get failed too")
        return
    count = 0
    for tests in walk(root, "testsRef"):
        tests_obj, _ = legacy_get(tests["testsRef"]["id"]["_value"])
        for summary in walk(tests_obj, "summaryRef"):
            s_obj, _ = legacy_get(summary["summaryRef"]["id"]["_value"])
            for att in walk(s_obj, "payloadRef"):
                name = att.get("name", {}).get("_value") or "attachment"
                fname = att.get("filename", {}).get("_value", "")
                ext = os.path.splitext(fname)[1] or ".png"
                dst = os.path.join(screens, safe(name) + ext)
                r = run("export", *extra, "--type", "file", "--path", xcresult,
                        "--id", att["payloadRef"]["id"]["_value"], "--output-path", dst)
                if r.returncode == 0:
                    count += 1
    notes.append(f"exported {count} attachment(s) with the legacy API")


if os.path.isdir(xcresult):
    if not export_attachments_new():
        export_attachments_legacy()
else:
    notes.append(f"{xcresult} not found (tests did not run)")

# ---------------------------------------------------------------- results
lines, failures = [], []

summary = run("get", "test-results", "summary", "--path", xcresult, "--compact") if os.path.isdir(xcresult) else None
if summary is not None and summary.returncode == 0:
    s = json.loads(summary.stdout)
    lines.append(f"Result: {s.get('result')} — total {s.get('totalTestCount')}, passed {s.get('passedTests')}, "
                 f"failed {s.get('failedTests')}, skipped {s.get('skippedTests')}")
    for f in s.get("testFailures", []):
        failures.append(f"[{f.get('targetName')}] {f.get('testName')}\n    {f.get('failureText')}")
elif summary is not None:
    notes.append("test-results summary unavailable: " + (summary.stderr or "").strip()[:300])

tests = run("get", "test-results", "tests", "--path", xcresult, "--compact") if os.path.isdir(xcresult) else None
if tests is not None and tests.returncode == 0:
    def cases(node, path):
        kind = node.get("nodeType")
        name = node.get("name", "")
        if kind == "Test Case":
            msgs = [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Failure Message"]
            lines.append(f"  [{node.get('result')}] {'/'.join(path + [name])}")
            for m in msgs:
                lines.append(f"      {m}")
            return
        sub = path + [name] if kind in ("Unit test bundle", "UI test bundle", "Test Suite") else path
        for c in node.get("children", []):
            cases(c, sub)
    lines.append("")
    lines.append("Test cases:")
    for n in json.loads(tests.stdout).get("testNodes", []):
        cases(n, [])

# Fallback / complement from the raw xcodebuild log.
if os.path.exists(log_path):
    log = open(log_path, errors="replace").read().splitlines()
    log_cases = [l for l in log if re.match(r"^Test [Cc]ase .*(passed|failed|skipped)", l)]
    log_fail = [l for l in log if re.search(r": error: -\[|error: .*XCT|Test Case .* failed", l)]
    if not any(l.startswith("  [") for l in lines):
        lines.append("")
        lines.append("Test cases (from xcodebuild log):")
        lines += ["  " + l for l in log_cases]
    if not failures:
        failures += log_fail
    tail = [l for l in log[-15:] if l.strip()]
    lines.append("")
    lines.append("xcodebuild log tail:")
    lines += ["  " + l for l in tail]

shots = sorted(os.listdir(screens))
with open(os.path.join(out_dir, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n\n")
    f.write("Screenshots:\n" + "".join(f"  {s}\n" for s in shots))
    f.write("\nNotes:\n" + "".join(f"  {n}\n" for n in notes))
with open(os.path.join(out_dir, "failures.txt"), "w") as f:
    f.write("\n".join(failures) + ("\n" if failures else ""))

print(open(os.path.join(out_dir, "summary.txt")).read())
if failures:
    print("FAILURES:\n" + "\n".join(failures))
