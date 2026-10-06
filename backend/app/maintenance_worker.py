"""Keep demo maintenance running while this process is alive."""
import argparse
import logging
import time
from .scheduled_jobs import run_once

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--once',action='store_true')
    parser.add_argument('--interval-seconds',type=int,default=60)
    args=parser.parse_args()
    if args.interval_seconds<10: parser.error('interval must be at least 10 seconds')
    logging.basicConfig(level=logging.INFO)
    while True:
        try: logging.info('Maintenance: %s',run_once())
        except Exception:
            logging.exception('Maintenance failed')
            if args.once: raise
        if args.once: return
        time.sleep(args.interval_seconds)

if __name__=='__main__': main()
