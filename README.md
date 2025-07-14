# HI-pfs

**Your IPFS network as easy and cheap one can say Hi!**

**Version:** 1.3.0
**Author:** CompMonks
**License:** MIT


A distributed IPFS node infrastructure designed for Raspberry Pi devices.

HI-pfs automates provisioning, failover and maintenance for an IPFS node cluster. The
repository is mainly a collection of shell scripts together with a small Python
server used for token based downloads.

## Key Features

- **Automated provisioning** of primary/secondary nodes
- **HTTPS gateway** through Caddy and Cloudflare
- **Token protected ZIP delivery** via a Flask server
- **Auto replication** of CIDs across all nodes
- **Role failover** based on a heartbeat file
- **Watchdog and self maintenance** tasks with optional email alerts

## Repository Layout

```
.
├── scripts/   # setup and maintenance scripts
│   ├── bootstrap.sh      # orchestrates initial install
│   ├── setup.sh          # configures IPFS, Caddy, etc.
│   ├── watchdog.sh       # service health checks
│   ├── role-check.sh     # promote/demote logic
│   ├── promote.sh / demote.sh
│   ├── server.py         # token server
│   └── ...
├── tests/    # unit tests for server
└── README.md
```

After installing on a node the following structure appears under the user
account:

```
/home/<user>/
├── ipfs-admin/
│   ├── shared-cids.txt
│   ├── logs/
│   ├── tokens/    zips/
├── token-server/
│   ├── server.py  generate_token.py
│   ├── zips/  tokens/  logs/ (symlinks)
└── scripts/
    ├── heartbeat.sh  promote.sh  role-check.sh  demote.sh
    ├── self-maintenance.sh  watchdog.sh  diagnostics.sh
```

## Node Roles & Failover

**Primary Node**
- Maintains `shared-cids.txt`
- Runs CID auto-sync and the token server
- Writes a heartbeat every minute

**Secondary Node**
- Pins CIDs from the primary every ten minutes
- Monitors the heartbeat; if it disappears for more than three minutes the node
  promotes itself

When the old primary rejoins it demotes automatically.

## Quick Start

1. Flash Raspberry Pi OS (64‑bit recommended) and boot the Pi.
2. (Optional) clean an existing install:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/init.sh)
   ```
3. Configure a Cloudflare tunnel and DNS for each node.
4. Bootstrap a node:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/bootstrap.sh)
   ```
   Follow the prompts for user, node name and tunnel information. Copy the
   `swarm.key` and `PEERS.txt` to other nodes before running the same command on
   them.

## Maintenance

- `watchdog.sh` restarts `ipfs`, `cloudflared` and `token-server` if they crash
- `self-maintenance.sh` performs daily package upgrades and can reboot
- Diagnostics and logs reside in `~/ipfs-admin/logs`

## Token Downloads

Generate a token on the primary node:
```bash
python3 ~/token-server/generate_token.py /path/to/folder
```
Download the ZIP from any node:
```
https://<node-domain>/download?token=<token>
```
A new token is automatically generated once the previous one is used.

## Running Tests

```bash
pip install pytest
pytest
```

This runs the unit tests found in the `tests/` directory.

Continuous integration on GitHub also checks all Python files with `pylint`.

## Learn More

Review each script in the `scripts/` folder to understand the setup process and
failover logic. Familiarity with IPFS, systemd services and Cloudflare tunnels is
recommended. Developers may also run `pylint` locally and consider
`shellcheck` for the bash scripts.

## License

This project is released under the MIT License.
