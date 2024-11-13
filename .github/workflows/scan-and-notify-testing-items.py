import requests
import os
import sys
import time
import json
from datetime import datetime, timedelta


GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"


def get_github_project_info(github_token, github_org, github_project):
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Content-Type": "application/json"
    }
    query = '''
    {
      organization(login: "%s") {
        projectsV2(first: 20) {
          nodes {
            id
            title
            number
          }
        }
      }
    }
    ''' % (github_org)
    payload = {
        "query": query
    }

    response = requests.post(GITHUB_GRAPHQL_URL, headers=headers, json=payload)
    if response.status_code == 200:
        # Find project by title
        print("Response: %s" % response.json())
        nodes = response.json().get("data").get("organization").get("projectsV2").get("nodes")
        for node in nodes:
            if node.get("title") == github_project:
                return node
    else:
        response.raise_for_status()


def get_current_sprint(github_token, project_id):
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Content-Type": "application/json"
    }
    query = '''
    query {
      node(id: "%s") {
        ... on ProjectV2 {
          fields(first: 20) {
            nodes {
              ... on ProjectV2IterationField {
                configuration {
                  iterations {
                    startDate
                    id
                  }
                }
              }
            }
          }
        }
      }
    }
    ''' % (project_id)

    payload = {
        "query": query
    }

    response = requests.post(GITHUB_GRAPHQL_URL, headers=headers, json=payload)
    if response.status_code == 200:
        # Find project by title
        result = response.json().get("data").get("node").get("fields").get("nodes")
        filtered_result = [node for node in result if 'configuration' in node]
        iterations = filtered_result[0].get("configuration").get("iterations")

        # Find current iteration
        current_date = datetime.now().date()
        current_iteration = None
        for iteration in iterations:
            start_date = datetime.strptime(iteration['startDate'], "%Y-%m-%d").date()
            end_date = start_date + timedelta(days=13)
            if start_date <= current_date <= end_date:
                current_iteration = iteration
                break

        return current_iteration
    else:
        response.raise_for_status()


def is_today_is_in_last_day_of_current_sprint(github_token, project_id):
    current_iteration = get_current_sprint(github_token, project_id)
    if current_iteration is None:
        print("Current sprint not found")
        return False

    current_date = datetime.now().date()
    end_date = datetime.strptime(current_iteration['startDate'], "%Y-%m-%d").date() + timedelta(days=13)

    return current_date == end_date


def list_issues_in_project(github_token, project_id, desired_status=None):
    headers = {
        "Authorization": f"bearer {github_token}",
        "Content-Type": "application/json"
    }

    query = """
    query($project: ID!, $cursor: String) {
      node(id: $project) {
        ... on ProjectV2 {
          items(first: 100, after: $cursor) {
            nodes {
              content {
                ... on Issue {
                  number
                  title
                  assignees(first: 10) {
                    nodes {
                      login
                    }
                  }
                }
              }
              status: fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                }
              }
              sprint: fieldValueByName(name: "Sprint") {
                ... on ProjectV2ItemFieldIterationValue {
                  title
                  startDate
                }
              }
            }
            pageInfo {
              endCursor
              hasNextPage
            }
          }
        }
      }
    }
    """

    cursor = None

    current_issues = []
    non_current_issues = []

    current_sprint = get_current_sprint(github_token, project_id)
    print(f"Current sprint: {current_sprint}")

    while True:
        variables = {"project": project_id, "cursor": cursor}
        response = requests.post(GITHUB_GRAPHQL_URL,
                                 headers=headers,
                                 json={"query": query, "variables": variables})

        if response.status_code == 200:
            data = response.json()
            items = data['data']['node']['items']['nodes']
            for item in items:
                status = item['status']['name']
                if desired_status and status not in desired_status:
                    continue
                sprint = item['sprint']
                if not sprint or not sprint.get('startDate') or not current_sprint or sprint['startDate'] != current_sprint['startDate']:
                    non_current_issues.append(item)
                else:
                    current_issues.append(item)

            page_info = data['data']['node']['items']['pageInfo']
            if page_info['hasNextPage']:
                cursor = page_info['endCursor']
            else:
                break
        else:
            raise Exception(f"Query failed to run by returning code of {response.status_code}. {response.text}")

    return current_issues, non_current_issues


def flatten_issues(title, blocks, issues, user_mapping):
    # Append the title and divider only if there are issues to display
    if issues:
        blocks.append(
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*{title}* - {len(issues)} issues"
                }
            }
        )
        blocks.append({"type": "divider"})

        # Combine issues into chunks of 5
        issue_texts = []
        for i, issue in enumerate(issues):
            number = issue["content"]["number"]
            title = issue["content"]["title"]
            issue_url = f"https://github.com/longhorn/longhorn/issues/{number}"
            assignees = []
            for assignee in issue["content"]["assignees"]["nodes"]:
                slack_id = user_mapping.get(assignee["login"])
                if not slack_id:
                    assignees.append(assignee["login"])
                else:
                    assignees.append(f"<@{slack_id}>")

            issue_texts.append(f"- *<{issue_url}|{number}>* - {title} - {', '.join(assignees)}")

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


def send_slack_notification(webhook_url, user_mapping,
                            current_issues, non_current_issues):
    if len(current_issues) == 0 and len(non_current_issues) == 0:
        print("Nothing to notify")
        return

    # Initialize blocks as an empty list
    blocks = []

    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": "Hello <!subteam^S033SUXF2Q7|longhorn-qa>, this is a reminder. \n\n" +
                    "There are 'Ready for Testing' or 'Testing' issues. Please finish verifying them using the corresponding sprint release soon. \n\n" +
                    "  - If passed, move them to 'Closed' and DO NOT change the sprint. \n" +
                    "  - If not passed, move them to 'Implementation' and update the sprint to the current one. \n\n" +
                    "Thanks for your efforts!"
        }
    })

    blocks = flatten_issues("Ready for Testing Issues from the Previous Sprint",
                            blocks, current_issues, user_mapping)
    blocks = flatten_issues("Ready for Testing Issues from older Sprints",
                            blocks, non_current_issues, user_mapping)

    payload = {
        "blocks": blocks
    }

    headers = {
        'Content-Type': 'application/json'
    }

    response = requests.post(webhook_url, json=payload, headers=headers)
    response.raise_for_status()


def scan_and_notify(github_org, github_repo, github_project):
    github_token = os.getenv("GITHUB_TOKEN")
    webhook_url = os.getenv("SLACK_WEBHOOK_URL")
    value = os.getenv("USER_MAPPING")
    user_mapping = {}
    if value is not None:
        user_mapping = json.loads(value)

    project = get_github_project_info(github_token, github_org, github_project)
    print(f"GitHub Project Details: {project}")

    # last_day = is_today_is_in_last_day_of_current_sprint(github_token, project.get("id"))
    # if not last_day:
    #     print("Today %s is not in last day of current sprint" % datetime.now().date())
    #     return

    project_id = project.get("id")
    current_issues, non_current_issues = list_issues_in_project(github_token,
                                                                project_id,
                                                                ["Ready For Testing", "Testing"])

    print("Number of \"Ready For Testing\" and \"Testing\" issues for current sprint:", len(current_issues))
    print("Number of \"Ready For Testing\" and \"Testing\" issues for non-current sprint:", len(non_current_issues))

    send_slack_notification(webhook_url,
                            user_mapping, current_issues, non_current_issues)


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print('Usage: python scan-and-notify-testing-items.py <github_org> <github_repo> <github_project>')

    scan_and_notify(sys.argv[1], sys.argv[2], sys.argv[3])
