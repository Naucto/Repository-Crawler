from loguru import logger as L
from github import Github, Auth


class Crawler:
    def __init__(self, token: str, source_organization: str, target_repository: str):
        auth = Auth.Token(token)
        self.gh = Github(auth=auth)

        L.info("Connected to GitHub")

        self.source = source_organization
        self.target = target_repository

    def __del__(self):
        self.gh.close()
        L.info("Done with GitHub. Goodbye!")

    def crawl(self):
        L.info("Gathering repository list from source organization")

        organization = self.gh.get_organization(self.source)
        unfiltered_repositories = organization.get_repos(type="all")

        mirrored_repositories = [
            repo for repo in unfiltered_repositories if not repo.archived and not repo.fork
        ]

        L.info("Found {} repositories, of which {} of them will be mirrored", unfiltered_repositories.totalCount, len(mirrored_repositories))
