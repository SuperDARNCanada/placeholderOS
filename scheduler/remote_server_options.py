#!/usr/bin/python3

# Copyright 2019 SuperDARN Canada
#
# remote_server_options.py
# 2019-04-25
# options class for remote server module

import json
import os

def ascii_encode_dict(data):
    ascii_encode = lambda x: x.encode('ascii')
    return dict(map(ascii_encode, pair) for pair in data.items())


class RemoteServerOptions(object):
    """
    Parses the options from the config file that are relevant to data writing.

    """
    def __init__(self):
        super(RemoteServerOptions, self).__init__()

        if not os.environ["BOREALISPATH"]:
            raise ValueError("BOREALISPATH env variable not set")
        config_path = os.environ["BOREALISPATH"] + "/config.ini"
        try:
            with open(config_path, 'r') as config_data:
                raw_config = json.load(config_data)
        except IOError:
            errmsg = 'Cannot open config file at {0}'.format(config_path)
            raise IOError(errmsg)

        self._site_id = raw_config["site_id"]

    @property
    def site_id(self):
        """
        Gets the 3 letter radar code of this radar.

        :return:    3 letter radar code
        :rtype:     str
        """
        return self._site_id


