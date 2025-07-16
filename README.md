# HI-pfs: A Distributed IPFS Node Infrastructure
**Your ipfs network as easy and cheap one can say Hi!** (or close enough 😉).

**Version:** 1.3.0  
**Author(s):** CompMonks. 
**Contributor(s):**  
**License:** MIT 


It is an open, free and community-driven project to enable as many creatives as possible to store and distribute their digital assets at their advantage. It is based on IPFS' _Open protocols to store, verify, and share data across distributed networks_ ([Link](https://ipfs.tech/)).


Join if you feel like that's needed!

![image](https://github.com/user-attachments/assets/ea32ff4e-e81b-4b62-83df-2d69ec9e8235)
Source: [Link](https://blog.ipfs.tech/2022-06-09-practical-explainer-ipfs-gateways-1/)

⸻

## 📌 Overview

HI-pfs is a robust, scalable, and self-maintaining network of IPFS nodes deployed on Raspberry Pi devices. It provides:

- Automated node provisioning (primary/secondary)
- Secure Cloudflare-based public gateway
- Token-protected ZIP delivery
- Auto-replication of shared CIDs
- Role failover and diagnostics

⸻

## 🚀 Features

- 🌐 HTTPS Reverse Proxy with optional Auth (Caddy + Cloudflare)
- 🔐 Token-based ZIP downloads from local admin folders
- 📦 CID auto-pinning and shared replication across nodes
- 🧠 Primary/Secondary roles with heartbeat detection and failover
- 🛡️ Watchdog + Email alerts + Daily self-updates
- 🧰 On-device diagnostics and logs

⸻

## 📁 File Structure (on each Pi after setup)
```
/home/<user>/
├── ipfs-admin/
│   ├── shared-cids.txt
│   ├── logs/
│   ├── tokens/ zips/
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
   - A stable internet connection, **LAN** or **WAN**

### 1. Flash and Boot Raspberry Pi
- Use Raspberry Pi Imager to flash Raspberry Pi OS Lite (64-bit recommended)
- Boot, configure Wi-Fi, hostname (opt. can be left by default. It will be changed later during setup)

### 2. Cleanup (Optional)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/init.sh) 
```
Use this command if your Pi is not a brand new install

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

## Token Download System
Generate a ZIP with a token (primary only):
```python3 ~/token-server/generate_token.py /path/to/folder```
Download URL:
```https://<node-domain>/download?token=<your-token>```

## CID Auto-Replication
- On primary: new CIDs pinned locally and appended to shared-cids.txt
- On secondaries: regularly fetch + pin new CIDs

## Maintenance & Monitoring
**Diagnostics**
```hi-pfs status````
Shows IPFS status, peers, storage, services, and sync logs.

**Watchdog**
- Checks IPFS, cloudflared, and token-server every 15min
- Restarts services and sends email alert if needed

**Self-Maintenance**
- Daily updates system, IPFS, cloudflared, and token-server
- Sends report email and reboots if needed

⸻

## Replication & Scaling
- To scale the network, clone the SD card
- Run `bootstrap.sh` on the new device and provide the previous node when asked
- Each new node joins, syncs CIDs, and adapts role

⸻

## Email Alerts
- All alerts (watchdog + maintenance) are emailed to configured address
- Logs are stored in ~/ipfs-admin/logs

⸻

## Troubleshooting
- `ipfs.service` not running → run `systemctl status ipfs`
- Can’t access WebUI → ensure cloudflared and caddy are active
- Not syncing CIDs → check `shared-cids.txt` and `cid-sync.log`

⸻

##Remote Upload Data (Access via SSH + shared folder)
- from your remote computer, SSH into your primary node
```
ssh <USERNAME>@<SUBDOMAIN>
```
where `<USERNAME>` is the admin user set for your primary node (be careful as your primary node may change. Check your logs first), `<SUBDOMAIN>` is your subdomain as set in cloudflare (eg. `ipfs0.yourdomain.com`).

- upload your folder
```
scp -r ./<LOCALFOLDER> <USERNAME>@<SUBDOMAIN>:/home/<USERNAME>/ipfs-admin/uploads/
```
where `<LOCALFOLDER>` is the folder you want to upload (make sure you run this command at the right location in your file system or adjust the folder path to be absolute)

- generate token
```
ssh <USERNAME>@<SUBDOMAIN>
python3 ~/token-server/generate_token.py ~/ipfs-admin/uploads/<LOCALFOLDER>
```
- you will then receive the token, the name of zipped folder and the download link by email
- Once the zip downloaded, the access token will be revoked and a new one will be generated and sent again by email.

## Running Tests

To execute the unit tests locally:

```bash
pip install pytest
pytest
```

This will run all tests under the `tests/` directory.

⸻

## Acknowledgements
- [IPFS](https://ipfs.tech/)
- [Cloudflare](https://www.cloudflare.com/en-gb/)
- [Caddy](https://caddyserver.com/)
- [Raspberry](https://www.raspberrypi.com/)
