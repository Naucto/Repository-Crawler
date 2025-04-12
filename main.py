#!/usr/bin/env python3

from loguru import logger as L

from crawler import Crawler
from hosting import WebhookListener

import os
import pwd


CW_TARGET_USER = "nrc"

L.info("Hello, world from Naucto's Repository Crawler!")

token  = os.getenv("CW_GITHUB_TOKEN")
source = os.getenv("CW_GITHUB_SOURCE")
target = os.getenv("CW_GITHUB_TARGET")

host      = bool(os.getenv("CW_HOST", None))
host_cert = os.getenv("CW_HOST_CERT", None)

if os.getuid() != 0:
    L.error("Naucto's Repository Crawler must start as root.")

try:
    ncr_pwnam = pwd.getpwnam(CW_TARGET_USER)
except KeyError:
    L.error("User '{}' does not exist on the system, cannot continue.")

os.setgid(ncr_pwnam.pw_gid)
os.setuid(ncr_pwnam.pw_uid)
L.info("Switching active user to '{}'", CW_TARGET_USER)

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
    if not host_cert:
        L.error("No HTTPS certificate path provided. Please set `CW_HOST_CERT` and try agian.")
        exit(1)

    host_cert_base = os.path.join(host_cert, "fullchain.pem")
    host_cert_key  = os.path.join(host_cert, "privkey.pem")

    listener = WebhookListener(crawler, host_cert=(host_cert_base, host_cert_key))
    listener.run()
else:
    crawler.crawl()
    crawler.commit()

L.info("Done working with GitHub. Goodbye!")
