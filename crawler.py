from loguru import logger as L
from github import Github, Auth

import tempfile

import os
import tarfile
import requests
import io


class Crawler:
    def __init__(self, token: str, source_organization: str, target_repository: str,
                       working_directory_path: str | None = None):
        auth = Auth.Token(token)
        self.gh = Github(auth=auth)

        L.debug("Connected to GitHub")

        self.source = source_organization
        self.target = target_repository

        self.working_directory = tempfile.TemporaryDirectory(dir=working_directory_path)

        L.debug("Working directory is located at {}", self.working_directory.name)

    def __del__(self):
        self.gh.close()
        L.info("Done with my work. Goodbye!")

        self.working_directory.cleanup()

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

        L.info("Done crawling through all repositories, preparing to upload to target repository")
