#!/usr/bin/env python

"""
    Synchronizes the local configuration with the configuration on phare.io. The local configuration
    always has precedence.
"""

import argparse
import json
import logging
import os
import sys
import urllib
import urllib.parse
from functools import reduce
from joblib import Parallel, delayed

import requests
from deepdiff import DeepDiff

logger = logging.getLogger("sync-with-phare")
logging.basicConfig(stream=sys.stdout, level=logging.INFO)

PHARE_TOKEN_FILE = os.getenv('PHARE_TOKEN_FILE')
PHARE_TOKEN = ""
PHARE_ENDPOINT = os.getenv('PHARE_ENDPOINT', "https://api.phare.io")


def list_monitors():
    """
    Returns a json representation of all monitors on phare.io which are visible for the account
    connected to the authentication token.

    :return: a json representation of the monitors on phare.io
    """
    r = requests.get(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors"),
                     headers={"Authorization": "Bearer " + PHARE_TOKEN},
                     timeout=10)
    return r.json()


def create_monitor(json_object):
    """
    Creates a monitor according to `json_object` on phare.io.

    :param json_object: a json representation of a monitor
    """
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors"),
                  data=json.dumps(json_object),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN,
                           "Content-Type": "application/json"},
                  timeout=10)


def update_monitor(id_, json_object):
    """
    Updates the monitor corresponding to id `id_` on phare.io with data in `json_object`.

    :param id_: id of a monitor
    :param json_object: a json representation of a monitor
    """
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors/" + str(id_)),
                  data=json.dumps(json_object),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN,
                           "Content-Type": "application/json"},
                  timeout=10)


def pause_monitor(id_):
    """
    Pauses the monitor corresponding to id `id_` on phare.io.

    :param id_: id of a monitor
    """
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors/" + str(id_) + "/pause"),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN},
                  timeout=10)


def resume_monitor(id_):
    """
    Resumes the monitor corresponding to id `id_` on phare.io.

    :param id_: id of a monitor
    """
    requests.post(urllib.parse.urljoin(PHARE_ENDPOINT, "uptime/monitors/" + str(id_) + "/resume"),
                  headers={"Authorization": "Bearer " + PHARE_TOKEN},
                  timeout=10)


def camel_to_snake(camel_case_string):
    """

    :param camel_case_string: an arbitrary string
    :return: the snake-case transformation of `camel_case_string`
    """
    return reduce(lambda x, y: x + ('_' if y.isupper() else '') + y.lower(), camel_case_string)


def as_snake(dct):
    """
    Transforms the keys in dictionary `dct` to snake-case.

    :param dct: a dictionary
    :return: the dictionary `dct` with snake-case keys
    """
    new_dct = {}
    for key, value in dct.items():
        new_dct[camel_to_snake(key)] = value
    return new_dct


def monitor_diff(local_monitor, phare_monitor):
    """
    Compares the monitors `local_monitor` and `phare_monitor` while ignoring runtime attributes
    and unused optional attributes.

    :param local_monitor: a json representation of a monitor
    :param phare_monitor: a json representation of a monitor
    :return: the difference between the monitors
    """
    ignored = ["root['id']", "root['response_time']", "root['updated_at']",
               "root['created_at']", "root['paused']", "root['status']"]

    if "project_id" not in local_monitor or local_monitor['project_id'] is None:
        ignored += ["root['project_id']"]
    if ("request" in local_monitor and "keyword" not in local_monitor["request"]
            or local_monitor["request"]["keyword"] is None):
        ignored += ["root['request']['keyword']"]

    return DeepDiff(local_monitor, phare_monitor, exclude_paths=ignored)


def sync_monitors(monitor_file):
    """
    Synchronizes the monitors on phare.io with the local monitor declarations.

    :param monitor_file: file containing JSON monitor declarations
    """
    phare_monitors = {monitor['name']: monitor for monitor in list_monitors()[
        'data']}
    local_monitors = json.load(monitor_file, object_hook=as_snake)

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


def pause_all_active_monitors():
    """
    Pauses all active monitors on phare.io.
    """
    active_monitors = filter(
        lambda monitor: not monitor["paused"], list_monitors()['data'])
    Parallel(n_jobs=5)(delayed(pause_monitor)(
        active_monitor['id']) for active_monitor in active_monitors)


def resume_all_inactive_monitors():
    """
    Resumes all inactive monitors on phare.io.
    """
    inactive_monitors = filter(
        lambda monitor: monitor["paused"], list_monitors()['data'])
    Parallel(n_jobs=5)(delayed(resume_monitor)(
        inactive_monitor['id']) for inactive_monitor in inactive_monitors)


def main():
    """
    Synchronizes the local configuration with the configuration on phare.io. The local configuration
    always has precedence.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=[
                        'sync-monitors', 'pause-all-monitors', 'resume-all-monitors'])
    parser.add_argument('--monitorfile', type=argparse.FileType('r'))
    args = parser.parse_args()

    match args.action:
        case "sync-monitors":
            sync_monitors(args.monitorfile)
        case "pause-all-monitors":
            pause_all_active_monitors()
        case "resume-all-monitors":
            resume_all_inactive_monitors()


if __name__ == '__main__':
    with open(PHARE_TOKEN_FILE, encoding='UTF-8') as f:
        PHARE_TOKEN = f.read()
        main()
