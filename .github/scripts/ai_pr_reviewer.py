#!/usr/bin/env python3
import os
import json
import urllib.request
import subprocess

def main():
    api_key = os.environ.get('GEMINI_API_KEY', '').strip()
    token = os.environ.get('GITHUB_TOKEN', '').strip()
    repo = os.environ.get('REPO', '').strip()
    pr_number = os.environ.get('PR_NUMBER', '').strip()
    base_sha = os.environ.get('BASE_SHA', '').strip()
    head_sha = os.environ.get('HEAD_SHA', '').strip()

    if not api_key:
        print("ℹ️ GEMINI_API_KEY is not configured. Skipping AI review.")
        return

    try:
        diff_bytes = subprocess.check_output(['git', 'diff', f'{base_sha}..{head_sha}'])
        diff = diff_bytes.decode('utf-8', errors='ignore')[:30000]
    except Exception as e:
        print(f"Could not get diff: {e}")
        diff = ''

    if not diff.strip():
        print("No diff found to review.")
        return

    system_prompt = (
        "You are a principal Flutter/Dart architect performing automated code review for "
        "dhc-tech/flutter-packages (packages: white_label_kit, dig_cli, apple_sign_in_plugin).\n\n"
        "Review this PR diff and structure your output in GitHub Markdown:\n"
        "1. 🛡️ **Security & Secrets**: Verify NO private keys, credentials, or proprietary client names exist.\n"
        "2. 💎 **Dart / Flutter Standards**: Strict typing, proper null safety, resource cleanup, async handling.\n"
        "3. ⚠️ **Breaking Changes**: Check public API contracts and version compatibility.\n"
        "4. 🧪 **Tests & Docs**: Ensure test coverage and docs are updated.\n\n"
        "Be concise, objective, and highlight any required improvements with code snippets."
    )

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [{"text": f"{system_prompt}\n\nDiff to review:\n```diff\n{diff}\n```"}]
            }
        ],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1500}
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req) as res:
            raw = json.loads(res.read().decode('utf-8'))
            review_text = raw['candidates'][0]['content']['parts'][0]['text']
    except Exception as e:
        print(f"Gemini API call failed: {e}")
        return

    comment_body = (
        f"## 🤖 Gemini AI PR Review\n\n"
        f"{review_text}\n\n"
        f"---\n"
        f"*Automated review powered by Google Gemini.*"
    )

    comment_url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"
    comment_req = urllib.request.Request(
        comment_url,
        data=json.dumps({'body': comment_body}).encode('utf-8'),
        headers={
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Flutter-AI-Reviewer'
        }
    )
    try:
        with urllib.request.urlopen(comment_req):
            print("Successfully posted Gemini AI review comment!")
    except Exception as e:
        print(f"Failed to post PR comment: {e}")

if __name__ == '__main__':
    main()
