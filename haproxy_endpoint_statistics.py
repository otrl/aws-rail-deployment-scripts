import re
import os
import urllib.parse
from collections import defaultdict

'''
A simple script to parse our exported papertrail logs to give a count on
how many times an endpoint was called.

Example output:

4312311	 GET /customers/[id]
443311 	 GET /orders/[id]
55555 	 GET /customers/[id]/orders

** Generated with the help of ChatGPT4
'''

def parse_haproxy_logs(log_folder):
    endpoint_counts = defaultdict(int)

    # Regular expression to match HAProxy log lines with method and URL
    log_pattern = re.compile(r'"(GET|POST|PUT|DELETE|PATCH) (/[^ ?]*)')

    # Regex to normalize numeric IDs and Java UUIDs (length of 32 characters)
    id_pattern = re.compile(r'/([a-fA-F0-9]{20,64}|\d+|OTRL.{0,10})')

    for log_file in os.listdir(log_folder):
        log_file_path = os.path.join(log_folder, log_file)
        if os.path.isfile(log_file_path) and (log_file.endswith(".log") or log_file.endswith(".tsv")):
            with open(log_file_path, 'r') as file:
                for line in file:

                    ## Change this for other services
                    if "service_cocs" not in line:
                        continue  # Skip lines that do not contain "service_cocs"

                    match = log_pattern.search(line)
                    if match:
                        method, url = match.groups()

                        # Decode URL-encoded components
                        url = urllib.parse.unquote(url)

                        # Normalize numeric IDs and Java UUIDs
                        normalized_url = id_pattern.sub('/[id]', url)

                        endpoint_counts[f"{method} {normalized_url}"] += 1

    # Print the result
    for endpoint, count in sorted(endpoint_counts.items(), key=lambda x: x[1], reverse=True):
        print(f"{count} \t {endpoint}")


if __name__ == "__main__":
    log_folder_path = "./log"  # Folder containing log files
    parse_haproxy_logs(log_folder_path)




