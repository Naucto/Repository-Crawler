from crawler import Crawler

from flask import Flask, request, jsonify
import flask.cli    

from loguru import logger as L
import logging


class WebhookListener:
    def __init__(self, crawler: Crawler, host='0.0.0.0', port=1987):
        self._crawler = crawler
        self._app     = Flask(__name__)

        self._host = host
        self._port = port

        # Make Flask shush -- we got our own logging messages instead.
        logging.getLogger('werkzeug').disabled = True
        flask.cli.show_server_banner = lambda *args: None

        L.info("The listener is available on {}:{}", host, port)

        @self._app.errorhandler(Exception)
        def on_error(exception):
            L.error("Unhandled exception occured: {}", exception)
            return jsonify({})

        @self._app.post("/")
        def on_push():
            github_event = request.headers.get("X-Github-Event")
            L.trace("Received a '{}' event", github_event)

            if github_event != "push":
                return jsonify({})

            github_event_body  = request.json()

            try:
                github_hash_before = github_event_body["before"]
                github_hash_after  = github_event_body["after"]
            except KeyError:
                L.debug("Bad request received, missing 'before' and 'after' fields")
                return jsonify({})

            L.debug("Push event, commit hashes from {} -> {}", github_hash_before, github_hash_after)

            if github_event_body["before"] == github_event_body["after"]:
                L.debug("Ignoring event, the commit hashes are the same")

            crawler.crawl()
            crawler.commit()
            crawler.clean_up()

            L.debug("Done handling the event, good night.")
            return {}

        L.info("Done setting up the Flask server. I'm ready!")

    def run(self):
        self._app.run(host=self._host, port=self._port, ssl_context='adhoc')
