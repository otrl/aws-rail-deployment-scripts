import re
import os
import urllib.parse
from collections import defaultdict

'''
How to Use:

Prepare your log files:
Place your HAProxy log files (with .log or .tsv extensions) in a folder named log in the same directory as the script.


Run the script:
Execute the script from the command line:

python haproxy_endpoint_statistics.py

Output:
The script will print a table of the top 20 endpoints (by request count) with columns for HTTP verb, normalized URL, 
request count, average response time, average response size, and counts of 2xx, 4xx, and 5xx responses.
'''

# Number of top endpoints to display
limit = 50

## Tweak these substitutions as needed
subs = [
    (re.compile(r'/jp/journeys/[^/]+/calling-points'), '/jp/journeys/[fare_id]/calling-points'),
    (re.compile(r'/(\d+)'), '/[id]'),
    (re.compile(r'/OTRL.{0,10}'), '/[id]'),
]

# Single regex to extract all needed fields
log_pattern = re.compile(
    r'\/(\d+)\s(\d+)\s+(\d+)\s+-.*?"(GET|POST|PUT|DELETE|PATCH|HEAD) ([^ ]+)'
)

def normalize_url(url, subs):
    for pattern, replacement in subs:
        url = pattern.sub(replacement, url)
    return url

def parse_haproxy_logs(log_folder):
    endpoint_stats = defaultdict(lambda: {
        'count': 0,
        'total_time': 0,
        'total_size': 0,
        '2xx': 0,
        '4xx': 0,
        '5xx': 0
    })

    for log_file in os.listdir(log_folder):
        log_file_path = os.path.join(log_folder, log_file)
        if os.path.isfile(log_file_path) and (log_file.endswith(".log") or log_file.endswith(".tsv")):
            with open(log_file_path, 'r') as file:
                for line in file:
                    if "otrl_haproxy" not in line:
                        continue

                    match = log_pattern.search(line)
                    if match:
                        resp_time, status, resp_size, method, url = match.groups()
                        url = urllib.parse.unquote(url)
                        normalized_url = normalize_url(url, subs)
                        key = f"{method} {normalized_url}"
                        stats = endpoint_stats[key]
                        stats['count'] += 1
                        stats['total_time'] += float(resp_time)
                        stats['total_size'] += int(resp_size)
                        status_int = int(status)
                        if 200 <= status_int < 300:
                            stats['2xx'] += 1
                        elif 400 <= status_int < 500:
                            stats['4xx'] += 1
                        elif 500 <= status_int < 600:
                            stats['5xx'] += 1

    print(f"{'Verb':<6} {'Url':<100} {'Count':<8} {'Avg Resp Time':<15} {'Avg Resp Size':<15} {'2xx':<6} {'4xx':<6} {'5xx':<6}")
    for endpoint, stats in sorted(endpoint_stats.items(), key=lambda x: x[1]['count'], reverse=True)[:limit]:
        avg_time = stats['total_time'] / stats['count'] if stats['count'] else 0
        avg_size = stats['total_size'] / stats['count'] if stats['count'] else 0
        verb, url = endpoint.split(' ', 1)
        print(f"{verb:<6} {url:<100} {stats['count']:<8} {avg_time:<15.2f} {avg_size:<15.2f} {stats['2xx']:<6} {stats['4xx']:<6} {stats['5xx']:<6}")


if __name__ == "__main__":
    log_folder_path = "./log"
    parse_haproxy_logs(log_folder_path)
