#!/usr/bin/env python3

from loguru import logger as L

from crawler import Crawler
from hosting import WebhookListener

import os


L.info("Hello, world from Naucto's Repository Crawler!")

token  = os.getenv("CW_GITHUB_TOKEN")
source = os.getenv("CW_GITHUB_SOURCE")
target = os.getenv("CW_GITHUB_TARGET")

host = bool(os.getenv("CW_HOST", None))

if host:
    L.info("Starting as a self-sustaining updater through a webhook endpoint.")

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

if host:
    listener = WebhookListener(crawler)
    listener.run()
else:
    crawler.crawl()
    crawler.commit()

L.info("Done working with GitHub. Goodbye!")
