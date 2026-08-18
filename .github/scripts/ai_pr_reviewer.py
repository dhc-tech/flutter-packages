#!/usr/bin/env python3
"""Gemini-powered PR review.

Posts a real GitHub PR *review* (not just an issue comment):
  - No issues found  -> APPROVE, with a short "no issues found" summary.
  - Issues found      -> REQUEST_CHANGES, with one inline comment per
                         issue anchored to its file/line, plus a summary.

Gemini is asked to return strict JSON so the result can drive the
review verdict and inline comments programmatically instead of being
pasted as a single freeform blob.
"""
import os
import re
import json
import time
import urllib.request
import urllib.error
import subprocess


def gemini_generate(api_key, prompt):
    """Call Gemini, preferring 2.5-pro for review quality but falling back to
    2.0-flash (much higher free-tier quota) on rate limiting, and retrying
    transient 429/5xx errors with backoff before giving up."""
    payload = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 4096,
            "responseMimeType": "application/json",
        },
    }
    last_err = None
    for model in ("gemini-2.5-pro", "gemini-2.0-flash"):
        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{model}:generateContent?key={api_key}"
        )
        for attempt in range(3):
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            try:
                with urllib.request.urlopen(req, timeout=90) as res:
                    raw = json.loads(res.read().decode("utf-8"))
                    return raw["candidates"][0]["content"]["parts"][0]["text"]
            except urllib.error.HTTPError as e:
                last_err = e
                if e.code == 429 or e.code >= 500:
                    time.sleep(2 ** attempt * 5)  # 5s, 10s, 20s
                    continue
                raise  # non-retryable (4xx other than 429)
            except Exception as e:
                last_err = e
                time.sleep(2 ** attempt * 5)
        print(f"{model} exhausted retries ({last_err}); trying next model.")
    raise last_err


def parse_diff_files(diff):
    """Map changed file -> set of valid RIGHT-side line numbers (added/context
    lines within added hunks), so inline comments only anchor to lines
    GitHub will actually accept for this diff."""
    files = {}
    current_file = None
    new_line = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:]
            files.setdefault(current_file, set())
            continue
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
        if m:
            new_line = int(m.group(1))
            continue
        if current_file is None or new_line is None:
            continue
        if line.startswith("+") and not line.startswith("+++"):
            files[current_file].add(new_line)
            new_line += 1
        elif line.startswith("-") and not line.startswith("---"):
            pass  # removed line, doesn't consume a new_line number
        else:
            new_line += 1
    return files


def post_review(repo, token, pr_number, head_sha, event, summary, comments):
    url = f"https://api.github.com/repos/{repo}/pulls/{pr_number}/reviews"
    payload = {
        "commit_id": head_sha,
        "body": summary,
        "event": event,
    }
    if comments:
        payload["comments"] = comments
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "Flutter-AI-Reviewer",
        },
    )
    try:
        with urllib.request.urlopen(req) as res:
            print(f"Posted {event} review with {len(comments)} inline comment(s).")
            return True
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        print(f"Review API failed ({e.code}): {body}")
        return False


def post_issue_comment(repo, token, pr_number, body):
    url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"
    req = urllib.request.Request(
        url,
        data=json.dumps({"body": body}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "Flutter-AI-Reviewer",
        },
    )
    with urllib.request.urlopen(req):
        pass


def main():
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    repo = os.environ.get("REPO", "").strip()
    pr_number = os.environ.get("PR_NUMBER", "").strip()
    base_sha = os.environ.get("BASE_SHA", "").strip()
    head_sha = os.environ.get("HEAD_SHA", "").strip()

    if not api_key:
        print("ℹ️ GEMINI_API_KEY is not configured. Skipping AI review.")
        return

    try:
        diff = subprocess.check_output(
            ["git", "diff", f"{base_sha}..{head_sha}"]
        ).decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"Could not get diff: {e}")
        return

    if not diff.strip():
        print("No diff found to review.")
        return

    valid_lines = parse_diff_files(diff[:60000])

    system_prompt = (
        "You are a principal Flutter/Dart architect performing an automated code "
        "review for dhc-tech/flutter-packages (packages: white_label_kit, dig_cli, "
        "apple_sign_in_plugin).\n\n"
        "Review the diff below for:\n"
        "1. Security & secrets — private keys, credentials, proprietary client names.\n"
        "2. Dart/Flutter standards — strict typing, null safety, resource cleanup, "
        "async/await correctness, memory leaks (unclosed streams/controllers).\n"
        "3. Breaking changes — public API contract or version compatibility.\n"
        "4. Missing tests/docs for new public behavior.\n"
        "5. Correctness bugs — logic errors, off-by-one, unhandled null/empty cases.\n\n"
        "Be thorough — do not skip files. Only report REAL, concrete issues you can "
        "point to a specific line for; do not invent nitpicks just to have something "
        "to say.\n\n"
        "Respond with STRICT JSON only, matching exactly this schema:\n"
        "{\n"
        '  "summary": "one short paragraph overview",\n'
        '  "issues": [\n'
        "    {\n"
        '      "file": "path/exactly/as/in/diff.dart",\n'
        '      "line": 123,\n'
        '      "severity": "blocking|warning|nit",\n'
        '      "comment": "what is wrong and how to fix it, with a code snippet if useful"\n'
        "    }\n"
        "  ]\n"
        "}\n"
        'If there are no real issues, return "issues": [].\n'
        '"line" must be the exact line number of an ADDED or CONTEXT line in the diff '
        "(the new-file line number), never a removed line."
    )

    try:
        raw_text = gemini_generate(api_key, f"{system_prompt}\n\nDiff to review:\n```diff\n{diff[:50000]}\n```")
    except Exception as e:
        print(f"Gemini API call failed: {e}")
        # Never fail silently — the PR should always show *something* rather
        # than a missing review with no explanation.
        post_issue_comment(
            repo, token, pr_number,
            "## 🤖 Gemini AI PR Review\n\n"
            f"⚠️ Review could not be generated right now ({e}). "
            "This will retry automatically on the next push to this PR.\n\n"
            "---\n*Automated review powered by Google Gemini.*",
        )
        return

    try:
        result = json.loads(raw_text)
        issues = result.get("issues", [])
        summary = result.get("summary", "").strip()
    except Exception as e:
        print(f"Could not parse Gemini JSON response: {e}\nRaw: {raw_text[:500]}")
        # Fall back to a plain comment so review feedback is never silently lost.
        post_issue_comment(
            repo, token, pr_number,
            "## 🤖 Gemini AI PR Review\n\n"
            "_Gemini's response could not be parsed as structured review output; "
            "raw output below._\n\n" + raw_text[:3000],
        )
        return

    # Anchor only comments that land on a real diff line; downgrade the rest
    # into the summary so nothing found is silently dropped.
    inline_comments = []
    unanchored = []
    for issue in issues:
        f = issue.get("file", "")
        line = issue.get("line")
        if f in valid_lines and line in valid_lines[f]:
            severity_emoji = {"blocking": "🚫", "warning": "⚠️", "nit": "💡"}.get(
                issue.get("severity", "warning"), "⚠️"
            )
            inline_comments.append({
                "path": f,
                "line": line,
                "body": f"{severity_emoji} **{issue.get('severity', 'warning').upper()}** — {issue.get('comment', '')}",
            })
        else:
            unanchored.append(issue)

    blocking_count = sum(1 for i in issues if i.get("severity") == "blocking")

    if not issues:
        body = (
            "## 🤖 Gemini AI PR Review\n\n✅ No issues found.\n\n"
            + (summary and f"{summary}\n\n" or "")
            + "---\n*Automated review powered by Google Gemini.*"
        )
        post_review(repo, token, pr_number, head_sha, "APPROVE", body, [])
        return

    extra = ""
    if unanchored:
        extra = "\n\n### Additional findings (outside the diff's changed lines)\n" + "\n".join(
            f"- **{i.get('file', '?')}**: {i.get('comment', '')}" for i in unanchored
        )

    body = (
        f"## 🤖 Gemini AI PR Review\n\n{summary}\n\n"
        f"Found **{len(issues)}** issue(s), **{blocking_count}** blocking.{extra}\n\n"
        "---\n*Automated review powered by Google Gemini.*"
    )
    event = "REQUEST_CHANGES" if blocking_count > 0 else "COMMENT"
    ok = post_review(repo, token, pr_number, head_sha, event, body, inline_comments)
    if not ok:
        # Inline anchoring failed (e.g. stale diff) — still surface the findings.
        post_issue_comment(repo, token, pr_number, body)


if __name__ == "__main__":
    main()
