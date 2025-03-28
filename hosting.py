from crawler import Crawler, CrawlerWorker

from flask import Flask, request, jsonify
import flask.cli

from gevent.pywsgi import WSGIServer
from gevent import ssl

from loguru import logger as L

import traceback


class WebhookListener:
    def __init__(self, crawler: Crawler, host: str='0.0.0.0', port: str=1987, host_cert: tuple[str, str]=None):
        self._crawler = crawler
        self._app     = Flask(__name__)

        self._host = host
        self._port = port

        self._host_cert = host_cert

        self._worker = CrawlerWorker(crawler)

        L.info("The listener is available on {}:{}", host, port)

        @self._app.errorhandler(Exception)
        def on_error(exception):
            L.error("Unhandled exception occured: {}", exception)
            L.trace(traceback.format_exc())

            return jsonify({}), 400

        @self._app.post("/")
        def on_push():
            github_event = request.headers.get("X-Github-Event")
            L.trace("Received a '{}' event", github_event)

            if github_event != "push":
                return jsonify({})

            github_event_body = request.get_json()

            try:
                github_hash_before = github_event_body["before"]
                github_hash_after  = github_event_body["after"]
            except KeyError:
                L.debug("Bad request received, missing 'before' and 'after' fields")
                return jsonify({})

            L.debug("Push event, commit hashes from {} -> {}", github_hash_before, github_hash_after)

            # TODO: Commit actual data
            self._worker.commit(None)

            if github_event_body["before"] == github_event_body["after"]:
                L.debug("Ignoring event, the commit hashes are the same")

            L.debug("Done handling the event, good night.")
            return jsonify({})

        L.info("Done setting up the Flask server. I'm ready!")

    def run(self):
        certfile = self._host_cert[0]
        keyfile  = self._host_cert[1]

        L.debug("Using {} as the certificate file", certfile)
        L.debug("Using {} as the key file", keyfile)

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile=certfile, keyfile=keyfile)

        server = WSGIServer(
            (self._host, self._port),
            self._app,
            ssl_context=ssl_context,
            do_handshake_on_connect=False
        )

        server.serve_forever()
