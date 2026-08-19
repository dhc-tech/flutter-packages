#!/usr/bin/env python3
import os
import json
import urllib.request

def main():
    api_key = os.environ.get('GEMINI_API_KEY', '').strip()
    token = os.environ.get('GITHUB_TOKEN', '').strip()
    repo = os.environ.get('REPO', '').strip()
    issue_number = os.environ.get('ISSUE_NUMBER', '').strip()
    title = os.environ.get('ISSUE_TITLE', '')
    body = os.environ.get('ISSUE_BODY', '')

    if not api_key:
        print("ℹ️ GEMINI_API_KEY is not configured. Skipping AI issue triage.")
        return

    prompt = (
        "You are an AI triage bot for the flutter-packages monorepo "
        "(containing: white_label_kit, dig_cli, apple_sign_in_plugin).\n\n"
        f"Issue Title: {title}\n"
        f"Issue Body: {body}\n\n"
        "Task:\n"
        "1. Identify target package (one of: 'p: white_label_kit', 'p: dig_cli', 'p: apple_sign_in_plugin', or 'question').\n"
        "2. Generate a helpful, concise initial response explaining next steps, troubleshooting tips, or asking for reproduction code if missing.\n\n"
        "Return JSON with schema:\n"
        "{\n"
        '  "label": "<chosen_label>",\n'
        '  "reply": "<markdown_reply_text>"\n'
        "}"
    )

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"}
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req) as res:
            raw = json.loads(res.read().decode('utf-8'))
            ai_content = json.loads(raw['candidates'][0]['content']['parts'][0]['text'])
    except Exception as e:
        print(f"Gemini API call failed: {e}")
        return

    label = ai_content.get('label', '')
    reply = ai_content.get('reply', '')

    # Apply label to Issue
    if label:
        label_url = f"https://api.github.com/repos/{repo}/issues/{issue_number}/labels"
        label_req = urllib.request.Request(
            label_url,
            data=json.dumps({'labels': [label]}).encode('utf-8'),
            headers={
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'AI-Triage-Bot'
            }
        )
        try:
            with urllib.request.urlopen(label_req):
                print(f"Successfully applied label '{label}' to issue #{issue_number}")
        except Exception as e:
            print(f"Failed to apply label: {e}")

    # Post Reply Comment
    if reply:
        comment_body = (
            f"## 🤖 Free AI Assistant (Gemini 2.0 Flash)\n\n"
            f"{reply}\n\n"
            f"---\n"
            f"*Automated triage response powered by Google Gemini Free Tier.*"
        )
        comment_url = f"https://api.github.com/repos/{repo}/issues/{issue_number}/comments"
        comment_req = urllib.request.Request(
            comment_url,
            data=json.dumps({'body': comment_body}).encode('utf-8'),
            headers={
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'AI-Triage-Bot'
            }
        )
        try:
            with urllib.request.urlopen(comment_req):
                print(f"Successfully posted triage response to issue #{issue_number}")
        except Exception as e:
            print(f"Failed to post comment: {e}")

if __name__ == '__main__':
    main()
