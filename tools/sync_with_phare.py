#!/usr/bin/env python

import argparse
import json
import logging
import os
import sys
import urllib
import urllib.parse
from functools import reduce

import requests
from deepdiff import DeepDiff

logger = logging.getLogger("sync-with-phare")
logging.basicConfig(stream=sys.stdout, level=logging.INFO)

PHARE_TOKEN_FILE = os.getenv('PHARE_TOKEN_FILE')
PHARE_TOKEN = ""
PHARE_ENDPOINT = os.getenv('PHARE_ENDPOINT', "https://api.phare.io")


def list_monitors():
    r = requests.get(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors"),
                     headers={"Authorization": "Bearer " + PHARE_TOKEN},
                     timeout=10)
    return r.json()


def create_monitor(json_object):
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors"),
                  data=json.dumps(json_object),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN,
                           "Content-Type": "application/json"},
                  timeout=10)


def update_monitor(id_, json_object):
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors/" + str(id_)),
                  data=json.dumps(json_object),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN,
                           "Content-Type": "application/json"},
                  timeout=10)


def pause_monitor(id_):
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors/" + str(id_) + "/pause"),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN},
                  timeout=10)


def resume_monitor(id_):
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors/" + str(id_) + "/resume"),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN},
                  timeout=10)


def camel_to_snake(camel_case_string):
    return reduce(lambda x, y: x + ('_' if y.isupper() else '') + y.lower(), camel_case_string)


def as_snake(dct):
    new_dct = {}
    for key, value in dct.items():
        new_dct[camel_to_snake(key)] = value
    return new_dct


def monitor_diff(local_monitor, phare_monitor):
    ignored = ["root['id']", "root['response_time']", "root['updated_at']",
               "root['created_at']", "root['paused']", "root['status']"]

    if "project_id" not in local_monitor or local_monitor['project_id'] is None:
        ignored += ["root['project_id']"]
    if ("request" in local_monitor and "keyword" not in local_monitor["request"]
            or local_monitor["request"]["keyword"] is None):
        ignored += ["root['request']['keyword']"]

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

            if monitor_diff(monitor, phare_monitors[name]):
                update_monitor(phare_monitors[name]['id'], monitor)
                logger.info("Updated monitor %s", name)
            else:
                logger.info("Monitor %s up-to-date with phare.io", name)
        else:
            create_monitor(monitor)
            logger.info("Created monitor %s", name)

    for name in phare_monitors.keys() - local_monitors.keys():
        pause_monitor(phare_monitors[name]['id'])
        logger.info("Paused monitor %s", name)


if __name__ == '__main__':
    with open(PHARE_TOKEN_FILE, encoding='UTF-8') as f:
        PHARE_TOKEN = f.read()
        main()
