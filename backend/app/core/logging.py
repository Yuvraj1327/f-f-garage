"""Logging setup."""

import logging


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        level=level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    # httpx logs every request URL at INFO. The Google Geocoding API takes its key as
    # a query parameter, so that line would put the server key in the log. Nothing
    # useful is lost: failures are still logged by the code that makes the calls.
    for noisy in ("httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
