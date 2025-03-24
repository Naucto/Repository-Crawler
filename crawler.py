from loguru import logger as L
from github import Github, Auth
from git import Repo, Actor

import tempfile

import os
import tarfile
import requests
import io
import shutil
import datetime


class Crawler:
    def __init__(self, token: str, source_organization: str, target_repository: str,
                       working_directory_path: str | None = None,
                       target_directory_path: str | None = None):
        auth = Auth.Token(token)
        self.gh = Github(auth=auth)

        L.debug("Connected to GitHub")

        self.source = source_organization
        self.target = target_repository

        self.working_directory = tempfile.TemporaryDirectory(dir=working_directory_path)
        L.debug("Working directory is located at {}", self.working_directory.name)

        self.target_directory = tempfile.TemporaryDirectory(dir=target_directory_path)
        L.debug("Target directory is located at {}", self.target_directory.name)

    def __del__(self):
        self.gh.close()
        L.info("Done with my work. Goodbye!")

        self.clean_up()

    def crawl(self):
        L.info("Gathering repository list from source organization")

        organization = self.gh.get_organization(self.source)
        unfiltered_repositories = organization.get_repos(type="all")

        mirrored_repositories = [
            repo for repo in unfiltered_repositories if not repo.archived and not repo.fork
        ]

        L.info("Found {} repositories, of which {} of them will be mirrored", unfiltered_repositories.totalCount, len(mirrored_repositories))

        for repo in mirrored_repositories:
            L.info("Crawling through repository {}", repo.full_name)

            repo_local_path = os.path.join(self.working_directory.name, repo.name)
            L.debug("Local path for repository is {}", repo_local_path)
            os.makedirs(repo_local_path)

            repo_tarball_url = repo.get_archive_link("tarball")
            
            L.debug("Opening tarball stream for repository at {}", repo_tarball_url)
            
            with requests.get(repo_tarball_url, stream=True) as tarball_stream, \
                 tarfile.open(fileobj=io.BytesIO(tarball_stream.raw.read()), mode="r:gz") as tarball:
                     root_folder_name = tarball.getmember(tarball.getnames()[0]).name
                     L.trace("Root folder name is {}", root_folder_name)

                     for member in tarball.getmembers():
                         initial_path = member.name
                         member.name = member.name.replace(root_folder_name, '', 1)[1:]
                         target_path = os.path.join(repo_local_path, member.name)

                         L.trace("Extracting member {} -> {}", initial_path, target_path)
                         tarball.extract(member, path=repo_local_path)

        L.info("Done crawling through all repositories")

    def commit(self):
        target_repo = Repo.clone_from(f'git@github.com:{self.target}.git', self.target_directory.name)
        L.info("Cloned target repository to {}", self.target_directory.name)

        for item in os.listdir(self.target_directory.name):
            if item == ".git":
                continue

            item_path = os.path.join(self.target_directory.name, item)
            if os.path.isdir(item_path):
                shutil.rmtree(item_path)
            else:
                os.remove(item_path)

            L.trace("Removed item {}", item_path)

        L.debug("Cleaned up target repository before mirroring")

        for item in os.listdir(self.working_directory.name):
            item_path = os.path.join(self.working_directory.name, item)
            target_path = os.path.join(self.target_directory.name, item)

            L.trace("Copying item {} -> {}", item_path, target_path)
            if os.path.isdir(item_path):
                shutil.copytree(item_path, target_path)
            else:
                shutil.copy2(item_path, target_path)

        target_repo.index.add("*")

        if not target_repo.index.diff("HEAD"):
            L.info("No changes detected, not commiting to target repository")
            return

        L.debug("Added all files to the index, {} files in total", len(target_repo.index.entries))

        target_commit_summary: str = ""

        if target_repo.head.is_valid():
            L.debug("Target repository has at least one commit, preparing commit summary")

            diff_name_status = target_repo.git.diff('HEAD', '--name-status')
            diff_numstat = target_repo.git.diff('HEAD', '--numstat')

            file_changes = {"A": [], "M": [], "D": []}
            rename_changes = []
            for line in diff_name_status.splitlines():
                parts = line.split("\t")
                change_type = parts[0]

                if change_type.startswith("R"):
                    if len(parts) >= 3:
                        rename_changes.append(f"{parts[1]} -> {parts[2]}")
                elif change_type in file_changes:
                    file_changes[change_type].append(parts[1])

            total_additions = 0
            total_deletions = 0
            for line in diff_numstat.splitlines():
                parts = line.split("\t")
                if len(parts) >= 3:
                    added_str, deleted_str, _ = parts
                    try:
                        added = int(added_str)
                        deleted = int(deleted_str)
                    except ValueError:
                        added, deleted = 0, 0
                    total_additions += added
                    total_deletions += deleted

                    target_commit_summary = f"""
    Summary of changes:
    Total additions: {total_additions} lines
    Total deletions: {total_deletions} lines
    Files added: {', '.join(file_changes['A']) if file_changes['A'] else 'None'}
    Files modified: {', '.join(file_changes['M']) if file_changes['M'] else 'None'}
    Files deleted: {', '.join(file_changes['D']) if file_changes['D'] else 'None'}
    """.strip()

            if rename_changes:
                target_commit_summary += f"\nFiles renamed: {', '.join(rename_changes)}\n"
        else:
            L.debug("Target repository has no commits, using default commit summary")
            target_commit_summary = "Initial commit"

        target_commit_date = datetime.datetime.now(tz=datetime.timezone.utc)
        target_commit_message = f"""Mirror of {self.source} on {target_commit_date.isoformat()}

{target_commit_summary}""".strip()

        target_repo.index.commit(
            message=target_commit_message,
            author=Actor("Naucto's Repository Crawler", "contact@naucto.net")
        )
        L.info("Committed changes to target repository under hash {}", target_repo.head.commit.hexsha)
        
        target_repo.remotes.origin.push()
        L.info("Pushed changes to remote repository")

    def clean_up(self):
        L.info("Cleaning up working directory")
        self.working_directory.cleanup()
