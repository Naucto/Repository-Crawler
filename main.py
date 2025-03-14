#!/usr/bin/env python3.13

from loguru import logger as L

import os

from crawler import Crawler


L.info("Hello, world from Naucto's Repository Crawler!")

token  = os.getenv("CW_GITHUB_TOKEN")
source = os.getenv("CW_GITHUB_SOURCE")
target = os.getenv("CW_GITHUB_TARGET")

if not token:
    L.error("No GitHub token provided. Please set `CW_GITHUB_TOKEN` and try again.")
    exit(1)
elif not source:
    L.error("No source organization provided. Please set `CW_GITHUB_SOURCE` and try again.")
    exit(1)
elif not target:
    L.error("No target organization provided. Please set `CW_GITHUB_TARGET` and try again.")
    exit(1)

crawler = Crawler(token, source, target)
crawler.crawl()
crawler.commit()

L.info("Done working with GitHub. Goodbye!")
