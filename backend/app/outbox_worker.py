"""Command-line worker that continuously publishes pending Firebase outbox events."""

import argparse
import time

from .outbox import publish_pending_events


def main() -> None:
    parser = argparse.ArgumentParser(description="Publish Shupick Firebase outbox events")
    parser.add_argument("--once", action="store_true", help="Publish one batch and exit")
    parser.add_argument("--batch-size", type=int, default=50)
    parser.add_argument("--interval-seconds", type=int, default=10)
    args = parser.parse_args()

    if not 1 <= args.batch_size <= 500:
        parser.error("--batch-size must be between 1 and 500")
    if not 1 <= args.interval_seconds <= 60:
        parser.error("--interval-seconds must be between 1 and 60")

    while True:
        result = publish_pending_events(args.batch_size)
        print(f"published={result['published']} failed={result['failed']}", flush=True)
        if args.once:
            return
        time.sleep(args.interval_seconds)


if __name__ == "__main__":
    main()
