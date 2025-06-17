import subprocess
import json
import os
import requests

REPOS = ["longhorn/longhorn-manager",
         "longhorn/longhorn-engine",
         "longhorn/longhorn-instance-manager",
         "longhorn/longhorn-share-manager",
         "longhorn/backing-image-manager",
         "longhorn/longhorn-ui",
         "longhorn/longhorn-spdk-engine",
         "longhorn/go-iscsi-helper",
         "longhorn/go-spdk-helper",
         "longhorn/backupstore",
         "longhorn/go-common-libs",
         "longhorn/types"]


def flatten_issues(repo, blocks, issues, user_mapping):
    # Append the title and divider only if there are issues to display
    print(issues)
    if issues:
        blocks.append(
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*{repo}* - {len(issues)} prs"
                }
            }
        )
        blocks.append({"type": "divider"})

        # Combine issues into chunks of 5
        issue_texts = []
        for i, issue in enumerate(issues):
            number = issue["number"]
            title = issue["title"]
            issue_url = f"https://github.com/{repo}/pull/{number}"
            reviewers = []
            for reviewer in issue["reviewers"]:
                slack_id = user_mapping.get(reviewer)
                if not slack_id:
                    reviewers.append(reviewer)
                else:
                    reviewers.append(f"<@{slack_id}>")

            issue_texts.append(f"- *<{issue_url}|{number}>* - {title} - {', '.join(reviewers)}")

            # Add a block for every 5 issues for avoiding bad request error
            if (i + 1) % 5 == 0 or (i + 1) == len(issues):
                blocks.append({
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "\n".join(issue_texts)  # Combine all issue texts
                    }
                })
                issue_texts = []  # Reset for the next chunk

    return blocks


def send_slack_notification(issues):
    github_token = os.getenv("GITHUB_TOKEN")
    webhook_url = os.getenv("SLACK_WEBHOOK_URL")
    value = os.getenv("USER_MAPPING")
    user_mapping = {}
    if value is not None:
        user_mapping = json.loads(value)

    print("Sending Slack notification...")

    # Initialize blocks as an empty list
    blocks = []

    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": "Hello, this is a Pull Request Review reminder. \n\n" +
                    "Please help review the following Pull Requests. Thanks for your efforts!"
        }
    })

    for repo in REPOS:
        print(f"Processing prs in {repo}...")
        blocks = flatten_issues(repo, blocks, issues[repo], user_mapping)

    payload = {
        "blocks": blocks
    }

    headers = {
        'Content-Type': 'application/json'
    }

    print(f"Payload: {json.dumps(payload, indent=2)}")

    response = requests.post(webhook_url, json=payload, headers=headers)
    response.raise_for_status()


def pr_review_reminder():
    """
    Fetches and prints details of open Pull Requests for a given repository.
    """

    issues = {repo: [] for repo in REPOS}

    for repo in REPOS:
        print(f"Checking PRs in {repo}...")
        # Construct the gh command
        command = [
            "gh", "pr", "list",
            "--repo", repo,
            "--state", "open",
            "--json", "number,title,author,reviewRequests,labels"
        ]

        try:
            # Run the command
            result = subprocess.run(command, capture_output=True, text=True, check=False)

            # Check if the command was successful
            if result.returncode != 0:
                print(f"  Error running gh command for {repo}:")
                if result.stdout:
                    print(f"  Stdout: {result.stdout.strip()}")
                if result.stderr:
                    print(f"  Stderr: {result.stderr.strip()}")
                continue

            # Check if there's any output to parse
            if not result.stdout.strip():
                print(f"  No open PRs found or no output from gh for {repo}.")
                continue

            # Parse the JSON output
            prs_data = json.loads(result.stdout)

            if not prs_data:
                print(f"  No open PRs found in {repo}.")
                continue

            # Iterate through each PR
            for pr in prs_data:
                pr_number = pr.get("number", "N/A")
                pr_title = pr.get("title", "N/A")
                pr_reviewers = pr.get("reviewRequests", [])
                labels = pr.get("labels", [])

                # Skip PR if its author is a bot
                if pr.get("author", {}).get("is_bot", False):
                    print(f"  Skipping PR #{pr_number} by bot author: {pr.get('author', {}).get('login', 'Unknown')}")
                    continue

                # Skip PR if it has "pending" label
                if any(label.get("name") == "pending" for label in labels):
                    print(f"  Skipping PR #{pr_number} due to 'pending' label.")
                    continue

                # Get author login
                author_info = pr.get("author")
                pr_author = "Unknown Author"
                if isinstance(author_info, dict):
                    pr_author = author_info.get("login", "Unknown Author")

                # Add PR details to issues list and classify using repos
                issues[repo].append({
                    "number": pr_number,
                    "title": pr_title,
                    "author": pr_author,
                    "reviewers": [reviewer.get("login", "Unknown") for reviewer in pr_reviewers],
                })
        except Exception as e:
            print(f"  An unexpected error occurred while processing {repo}: {e}")
        finally:
            print()

    send_slack_notification(issues)


if __name__ == "__main__":
    pr_review_reminder()
