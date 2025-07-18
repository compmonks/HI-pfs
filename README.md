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
│   ├── server.py generate_token.py
│   ├── zips/ tokens/ logs/ (symlinks)
├── scripts/
│   ├── heartbeat.sh promote.sh role-check.sh demote.sh
│   ├── self-maintenance.sh watchdog.sh diagnostics.sh
```

⸻

## 🧑‍💻 Installation Instructions

### 0. Requirements
   - Hardware:
     - tested on a **Raspberry Pi 4B** with 4GB RAM min.
     - **SD card 16GB** class 10 U3 min.
     - **SSD external Hard Drive formatted to ext4** 1TB seems a good size to start with.
	  - a keyboard, a mouse and a monitor at least for the install and debugging steps
     - your necessary cables to plug and power everything together
     - a case for the Pi to enhance cooling (eg. consider passive cooling for minimal energy consumption), and tidy up the system.
   - Software:
      - **Raspberry Pi OS 64 Lite or Desktop (easier)**. You can use Rapberry Pi Imager for that. There is a copy of the tested version you can use to replicate if you want.
      - An existing web domain that you own.
      - A Cloudflare account (can be created later in the process).
     - **Kubo (IPFS CLI)**. The setup will automatically download and install the latest release from [dist.ipfs.tech](https://dist.ipfs.tech/) if the `ipfs` command is missing. `self-maintenance.sh` also keeps Kubo up to date.
   - A stable internet connection, **LAN** or **WAN**

### 1. Flash and Boot Raspberry Pi
- Use Raspberry Pi Imager to flash Raspberry Pi OS Lite (64-bit recommended)
- Boot, configure Wi-Fi, hostname (opt. can be left by default. It will be changed later during setup)

### 2. Cleanup (Optional)
`bootstrap.sh` now integrates the cleanup procedure formerly provided by
`init.sh`. When launching the bootstrap you will be prompted to run this
cleanup first. Choose **y** if you are reusing a Pi or recovering from a failed
install. You can still execute `init.sh` manually if needed.

### 3. Cloudflare Tunnel Setup
Hostnames and subdomains are generated automatically by `bootstrap.sh`. The first
node uses `ipfs-node-00` and `ipfs0.yourdomain.com`. When adding a new node, the
script asks for the hostname or IP of the previous node to derive the next names.

**If you own a domain already and want to keep things together, a subdomain might be a good choice to link your ipfs network to. Feel free to try other scenarios and share your steps with a pull so we can document it here and make it accessible for others. You may also want to consider to do this step at once for all your nodes (if you know how many you will have), or do it progressively every time you want to scale your network with a new node (one node and Pi at a time).**

**CLOUDFLARE SETUP**
- Go to [Cloudflare](https://www.cloudflare.com/) and create an account with a **FREE** plan (or more if you want).
- Add your full domain name: `yourdomain.com` with an auto scan and **check if all your DNS entries are there**. Otherwise add the missing ones manually. If your website was in a way for example that your frontend is hosted elsewhere and needs to access your backend by a subdomain (eg. `backend.yourdomain.com`), you will need to disable proxy for your `www`, `@` and `backend` DNS entries in cloudflare, redeploy your frontend, and check if your website works again and (optionally) reactivates the proxies afterwards.
- Follow the steps to change your DNS servers. It might vary from one domain provider to another.
- Go to DNS tab, click Add Record:
	- Type: `NS`
	- Name: `ipfs0` (this makes `ipfs0.yourdomain.com`)
   - Content: `ipfs0.ns.cloudflare.com` (Cloudflare name servers)    
-> Repeat this step for each node you want to create 
 
**DOMAIN PROVIDER SETUP**
These steps may vary depending on your domain provider:
- Go to your DNS zone entries
- Add an NS record for the subdomain:
	- Subdomain: `ipfs0`
	- Type: `NS`
	- Target: Same Cloudflare name servers as above (eg. `ipfs0.ns.cloudflare.com`)
-> Repeat this step for each node you want to create

- This delegates `ipfs0.yourdomain.com` to Cloudflare while keeping the rest of your domain on your domain provider. Wait for Cloudflare to have propagated the changes and check that your website and emails are working. This may take more than 24H. Check the scheduled operations in your domain provider to make sure. If you have deactivated DNSSEC in your domain provider and would like to reactivate it, you can then do so by going to the panel of your domain on Cloudflare DNS > Settings > DNSSEC > Activate.
- Once the domain is properly activated on Cloudflare, for to SSL/TLS > Choose **Full** or **Full (Strict)** Encryption if your origin has SSL. Also enable **Always use HTTPS**.

**WARNING : YOUR WEBSITE FRONTEND OR OTHER MIGHT FAIL BECAUSE OF CLOUDFLARE PROXY**. If that's the case, you will need to troubleshoot this as it depends of your setup.
 
### 4. Bootstrap the node
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/bootstrap.sh)
```

- Respond to prompts: user (same as Pi admin), Cloudflare domain and SSD size.
- For additional nodes, provide the previous node hostname or IP when prompted.
- Once you are done with setting up the first node, don't forget to copy the `swarm.key` and `PEERS.txt` files to other nodes before setup in order to liknk them properly. Follow instructions during the first setup.

## Node Roles & Behavior
**Primary Node:**
- Maintains shared-cids.txt
- Runs cid_autosync and token server
- Sends heartbeat to file every 60s

**Secondary Node:**
- Pull shared CIDs every 10 min
- Monitor heartbeat to promote if necessary

**Failover Logic:**
- If primary heartbeat is missing for >3 min, a secondary promotes itself
- Previous primary will demote if it rejoins

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

## Replication & Scaling

- To scale the network, clone the SD card
- Run `bootstrap.sh` on the new device and provide the previous node when asked
- Each new node joins, syncs CIDs, and adapts role

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
