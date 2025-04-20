#!/usr/bin/env python

from deepdiff import DeepDiff
from functools import reduce
import argparse
import os
import requests
import urllib
import json
import logging
import urllib.parse
import sys

logger = logging.getLogger("sync-with-phare")
logging.basicConfig(stream=sys.stdout, level=logging.INFO)

phare_token_file = os.getenv('PHARE_TOKEN_FILE')
phare_token = ""
phare_endpoint = os.getenv('PHARE_ENDPOINT', "https://api.phare.io")


def list_monitors():
    r = requests.get(urllib.parse.urljoin(phare_endpoint, "uptime/monitors"),
                     headers={"Authorization": "Bearer " + phare_token})
    return r.json()


def create_monitor(json):
    requests.post(urllib.parse.urljoin(phare_endpoint, "uptime/monitors"),
                  data=json,
                  headers={"Authorization": "Beaer " + phare_token,
                           "Content-Type": "application/json"})


def update_monitor(id, json):
    requests.post(urllib.parse.urljoin(phare_endpoint, "uptime/monitors", id),
                  data=json,
                  headers={"Authorization": "Beaer " + phare_token,
                           "Content-Type": "application/json"})


def pause_monitor(id):
    requests.post(urllib.parse.urljoin(phare_endpoint, "uptime/monitors", id, "pause"),
                  headers={"Authorization": "Beaer " + phare_token})


def resume_monitor(id):
    requests.post(urllib.parse.urljoin(phare_endpoint, "uptime/monitors", id, "resume"),
                  headers={"Authorization": "Beaer " + phare_token})


def camel_to_snake(camel_case_string):
    return reduce(lambda x, y: x + ('_' if y.isupper() else '') + y.lower(), camel_case_string)


def as_snake(dct):
    new_dct = {}
    for key, value in dct.items():
        new_dct[camel_to_snake(key)] = value
    return new_dct


def monitor_diff(local_monitor, phare_monitor):
    ignored = ["root['id']", "root['response_time']", "root['response_time']", "root['updated_at']",
               "root['created_at']", "root['paused']", "root['status']"]

    if "project_id" not in local_monitor:
        ignored += "root['project_id']"
    if "request" not in local_monitor and "keyword" not in local_monitor["request"]:
        ignored += "root['request']['keyword']"

    return DeepDiff(local_monitor, phare_monitor, exclude_paths=ignored)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--monitorfile', type=argparse.FileType('r'))
    args = parser.parse_args()

    phare_monitors = {monitor['name']: monitor for monitor in list_monitors()[
        'data']}
    local_monitors = json.load(args.monitorfile, object_hook=as_snake)

    for name, monitor in local_monitors.items():
        if name in phare_monitors:
            if phare_monitors[name]['paused']:
                resume_monitor(phare_monitors[name]['id'])
                logger.info("Resumed monitor %s", name)

            if not monitor_diff(monitor, phare_monitors[name]):
                update_monitor(phare_monitors[name]['id'], monitor)
                logger.info("Updated monitor %s", name)

            logger.info("Monitor %s up-to-date with phare.io", name)
        else:
            create_monitor(monitor)
            logger.info("Created monitor %s", name)

    for name in phare_monitors.keys() - local_monitors.keys():
        pause_monitor(phare_monitors[name]['id'])
        logger.info("Paused monitor %s", name)


if __name__ == '__main__':
    with open(phare_token_file) as f:
        phare_token = f.read()
        main()
