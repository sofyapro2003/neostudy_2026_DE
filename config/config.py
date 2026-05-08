import json
from pathlib import Path

CONFIG_PATH = Path(__file__).parent / 'config.json'


def load_config():

    with open(CONFIG_PATH, 'r') as config_file:
        return json.load(config_file)
