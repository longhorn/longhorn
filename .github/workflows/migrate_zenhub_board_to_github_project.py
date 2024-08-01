import requests
import os
import jq
import sys


GITHUB_API_URL = "https://api.github.com"
GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"
ZENHUB_API_URL = "https://api.zenhub.com/p1/repositories/{repo_id}/board"


def get_github_repo_id(github_token, github_org, github_repo):
    url = f"{GITHUB_API_URL}/repos/{github_org}/{github_repo}"
    headers = {
        "Authorization": github_token
    }

    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json().get("id")
    else:
        response.raise_for_status()


def get_zenhub_board(zenhub_token, github_repo_id):
    url = ZENHUB_API_URL.format(repo_id=github_repo_id)
    headers = {
        "Content-Type": "application/json",
        "X-Authentication-Token": zenhub_token
    }

    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json()
    else:
        response.raise_for_status()


def get_github_issue(github_token, github_org, github_repo, issue_number):
    url = f"https://api.github.com/repos/{github_org}/{github_repo}/issues/{issue_number}"
    headers = {
        "Authorization": f"token {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }

    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json()
    else:
        response.raise_for_status()


def get_github_project(github_token, github_org, github_repo, project_number):
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Content-Type": "application/json"
    }
    query = '''
    query {
      repository(owner: "%s", name: "%s") {
        projectV2(number: %d) {
          id
          title
          fields(first: 20) {
            nodes {
              ... on ProjectV2FieldCommon {
                id
                name
              }
              ... on ProjectV2SingleSelectField {
                id
                name
                options {
                  id
                  name
                }
              }
            }
          }
        }
      }
    }
    ''' % (github_org, github_repo, project_number)
    payload = {
        "query": query
    }

    response = requests.post(GITHUB_GRAPHQL_URL, headers=headers, json=payload)
    if response.status_code == 200:
        return response.json().get("data").get("repository").get("projectV2")
    else:
        response.raise_for_status()


def get_github_project_status(github_token, github_org, github_repo, project_number):
    project = get_github_project(github_token, github_org, github_repo, project_number)
    nodes = project.get("fields").get("nodes")
    for node in nodes:
        if node.get("name") == "Status":
            return node.get("id"), {option.get("name"): option.get("id") for option in node.get("options")}


def get_github_project_estimate(github_token, github_org, github_repo, project_number):
    project = get_github_project(github_token, github_org, github_repo, project_number)
    nodes = project.get("fields").get("nodes")
    for node in nodes:
        if node.get("name") == "Estimate":
            return node.get("id")


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
        # fine project by title
        for project in response.json().get("data").get("organization").get("projectsV2").get("nodes"):
            if project.get("title") == github_project:
                return project
    else:
        response.raise_for_status()


def add_github_project_item(github_token, project_id, content_id):
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Content-Type": "application/json"
    }
    query = '''
    mutation {
      addProjectV2ItemById(input: {projectId: "%s", contentId: "%s"}) {
        item {
          id
        }
      }
    }
    ''' % (project_id, content_id)
    payload = {
        "query": query
    }

    response = requests.post(GITHUB_GRAPHQL_URL, headers=headers, json=payload)
    return response.json()


def move_item_to_status(github_token, project_id, item_id, field_id, single_select_option_id):
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Content-Type": "application/json"
    }
    query = '''
    mutation {
      updateProjectV2ItemFieldValue(input: {projectId: "%s", itemId: "%s", fieldId: "%s", value: {singleSelectOptionId: "%s"}}) {
        projectV2Item {
          id
        }
      }
    }
    ''' % (project_id, item_id, field_id, single_select_option_id)
    payload = {
        "query": query
    }

    response = requests.post(GITHUB_GRAPHQL_URL, headers=headers, json=payload)
    if response.status_code == 200:
        return response.json()
    else:
        response.raise_for_status()


def set_item_estimate(github_token, project_id, item_id, field_id, value):
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Content-Type": "application/json"
    }
    query = f'''
    mutation {{
      updateProjectV2ItemFieldValue(input: {{projectId: "{project_id}", itemId: "{item_id}", fieldId: "{field_id}", value: {{number: {value}}}}}) {{
        projectV2Item {{
          id
        }}
      }}
    }}
    '''
    payload = {
        "query": query
    }

    response = requests.post(GITHUB_GRAPHQL_URL, headers=headers, json=payload)
    if response.status_code == 200:
        return response.json()
    else:
        response.raise_for_status()


def check_zenhub_pipelins_github_project_status_match(board, status):
    zenhub_pipelines = [pipeline['name'] for pipeline in board['pipelines']]
    github_project_statuses = list(status.keys())
    for pipeline in zenhub_pipelines:
        if pipeline not in github_project_statuses:
            raise Exception(f"Pipeline '{pipeline}' not found in GitHub Project statuses")


def migrate_tickets(github_org, github_repo, github_project):
    github_token = os.getenv("GITHUB_TOKEN")
    zenhub_token = os.getenv("ZENHUB_TOKEN")

    # Get the GitHub Project details
    project = get_github_project_info(github_token, github_org, github_project)
    print(f"GitHub Project Details: {project}")
    project_number = project.get("number")
    project_id = project.get("id")
    status_node_id, status = get_github_project_status(github_token, github_org, github_repo, project_number)
    print(f"GitHub Project Details: number={project_number}, id={project_id}, status node_id={status_node_id}, status={status}")

    estimate_node_id = get_github_project_estimate(github_token, github_org, github_repo, project_number)
    print(f"GitHub Project Details: number={project_number}, id={project_id}, estimate node_id={estimate_node_id}")

    # Get the ZenHub board details
    github_repo_id = get_github_repo_id(github_token, github_org, github_repo)
    print(f"GitHub Repo ID: {github_repo_id}")
    board = get_zenhub_board(zenhub_token, github_repo_id)

    # Check pipelines of the ZenHub board and status of the GitHub Project are matching using for loop
    check_zenhub_pipelins_github_project_status_match(board, status)

    for pipeline in board['pipelines']:
        # Iterating through each pipeline, which are corresponding to the GitHub Project statuses (columns)
        column_name = pipeline['name']

        # Iterating through each ticket in the pipeline,
        # and creating a corresponding GitHub issue
        for issue in pipeline['issues']:
            print("Issue: ", issue)
            print(f"Processing issue: {issue['issue_number']} in pipeline: {column_name}")
            issue_info = get_github_issue(github_token, github_org, github_repo,
                                          issue['issue_number'])

            result = add_github_project_item(github_token,
                                             project_id, issue_info['node_id'])
            item_id = result['data']['addProjectV2ItemById']['item']['id']
            move_item_to_status(github_token,
                                project_id, item_id,
                                status_node_id,
                                status[column_name])
            # check if estimate is exist
            if 'estimate' in issue:
                print(f"Setting estimate: {issue['estimate'].get('value')} for issue: {issue['issue_number']}")
                set_item_estimate(github_token,
                                  project_id, item_id,
                                  estimate_node_id, issue['estimate'].get('value'))


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print('Usage: python migrate_zenhub_board_to_github_project.py <github_org> <github_repo> <github_project>')
        sys.exit()

    migrate_tickets(sys.argv[1], sys.argv[2], sys.argv[3])
