# CLAUDE.md

aws-rail-deployment-scripts is the helper tooling that grew around `aws-rail-deployment`: EC2 test-instance lifecycle management, container build and scan helpers, and an HAProxy statistics script. There is no README.

Dormant. It retires with the Docker Swarm platform.

## Layout

- `test-instances/` — the bulk of it: EC2 test-instance lifecycle automation, mostly **Perl**, with one Python script and a Node Slack notifier under `ec2_notify/`.
- `docker/` — container build, scan and entrypoint helpers.
- `haproxy_endpoint_statistics.py`, `utilities/cmdaemon` — standalone one-offs.

## Things that are not obvious

- **These start and stop real EC2 instances on a schedule.** `ec2_nightly_shutdown.pl` and `ec2_morning_startup.pl` are cost-control automation acting on live dev boxes; running one by hand affects other people's machines.
- **Perl, Python and Node in one repo with no shared tooling** — no dependency manifest for the Perl scripts, no tests, no CI. Each script stands alone.
- There are two Docker entrypoints because one variant is AWS-specific. Check which an image uses before editing either.
