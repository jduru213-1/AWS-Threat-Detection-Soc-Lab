# Create AWS indexes in Splunk (aws_cloudtrail, aws_config, aws_vpcflow).
# Targets the default Splunk in soc/ (Docker): localhost:8089, admin user.
# Usage: python setup_splunk.py

import getpass
import importlib

try:
    client = importlib.import_module("splunklib.client")
except ImportError as e:
    raise ImportError(
        "The Splunk Python SDK is required but not installed.\n"
        "Install it with:\n"
        "    pip install splunk-sdk\n"
        "and then re-run this script."
    ) from e

# Local Docker Compose defaults (see soc/docker-compose.yml).
SPLUNK_HOST = "localhost"
SPLUNK_PORT = 8089
SPLUNK_USERNAME = "admin"

# Indexes the lab uses; must exist before the Add-on sends data.
DEFAULT_INDEXES = [
    "aws_cloudtrail",
    "aws_config",
    "aws_vpcflow",
]


def connect_splunk(password: str):
    """Connect to the local lab Splunk (self-signed TLS → verify disabled)."""
    return client.connect(
        host=SPLUNK_HOST,
        port=SPLUNK_PORT,
        username=SPLUNK_USERNAME,
        password=password,
        scheme="https",
        verify=False,
    )


def ensure_indexes(service, index_names):
    """Create each index if it doesn't exist."""
    for name in index_names:
        if name in service.indexes:
            print(f"[indexes] {name} already exists")
        else:
            service.indexes.create(name)
            print(f"[indexes] {name} created")


def main():
    password = getpass.getpass(prompt="Enter your Splunk password: ")
    service = connect_splunk(password)
    ensure_indexes(service, DEFAULT_INDEXES)
    print("[setup] Splunk setup complete")


if __name__ == "__main__":
    main()
