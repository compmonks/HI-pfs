# HI-pfs
**Your ipfs network as easy and cheap one can say Hi!**\

Hi-pfs is an open, free and community-driven project to enable as many creatives as possible to store and distribute their digital assets at their advantage.

Join if you feel like that's needed!

## Requirements
   - Hardware:
     - tested on a **Raspberry Pi 4B**
     - **SD card 16GB**
     - **SSD 1TB min**
     - your necessary cables to plug and power everything together
     - a case for the rpi to enhance cooling (eg. Argon M2 or anything else you like), and tidy up the system.
   - Software:
      - **Raspberry Pi OS 64 Lite or Desktop (easier)**. You can use Rapberry Pi Imager for that. There is a copy of the tested version you can use to replicate if you want.
      - An existing web domain that you own.
      - A Cloudflare account (can be created later in the process).
   - A stable internet connection, **LAN** or **WAN**

### Scenario A: Use a subdomain from your existing domain (recommended)

## Setup (for each node/Pi)
0. On your PI 
   - Create or update your hostname so it follows a logic across your network (eg. ipfs-host-00, ipfs-host-01, etc... ).
   - Decide on a similarly consitent name for your node and write it down (eg. ipfs-node-00, ipfs-node-01, etc...).
   - Same thing for the subdomains we will be using (eg. ipfs0.yourdomain.com, ipfs1.yourdomain.com, etc...)

   So in the end, for each node/Pi you have:
      - a unique hostname: eg. `ipfs-host-00`
      - a unique node name: eg. `ipfs-node-00`
      - a unique subdomain name: eg. `ipfs0.yourdomain.com`

1. Create a subdomain (eg. `ipfs0.yourdomain.com`).
   
    If you own a domain already and want to keep things together, a subdomain might be a good choice to link your ipfs network to. Feel free to try other scenarios and share your steps with a pull so we can document it here and make it accessible for others.

   **CLOUDFLARE SETUP**
    - Go to [Cloudflare](https://www.cloudflare.com/) and create an account with a **FREE** plan (or more if you want).
    - Add your full domain name: `yourdomain.com` with an auto scan and **check if all your DNS entries are there**. Otherwise add the missing ones manually. If your website was in a way for example that your frontend is hosted elsewhere and needs to access your backend by a subdomain (eg. `backend.yourdomain.com`), you will need to disable proxy for your `www`, `@` and `backend` DNS entries in cloudflare, redeploy your frontend, and check if your website works again and (optionally) reactivates the proxies afterwards.
      
    - Follow the steps to change your DNS servers. It might vary from one domain provider to another.
    - Go to DNS tab, click Add Record:
      - Type: `NS`
      - Name: `ipfs0` (this makes `ipfs0.yourdomain.com`)
      - Content: `ipfs0.ns.cloudflare.com` (Cloudflare name servers)
   
   **DOMAIN PROVIDER SETUP**
   These steps may vary depending on your domain provider:
   - Go to your DNS zone entries
   - Add an NS record for the subdomain:
      - Subdomain: `ipfs0`
      - Type: `NS`
      - Target: Same Cloudflare name servers as above (eg. `ipfs0.ns.cloudflare.com`)

   This delegates `ipfs0.yourdomain.com` to Cloudflare while keeping the rest of your domain on your domain provider.
   Wait for Cloudflare to have propagated the changes and check that your website and emails are working. This may take more than 24H. Check the scheduled operations in your domain provider to make sure. If you have deactivated DNSSEC in your domain provider and would like to reactivate it, you can then do so by going to the panel of your domain on Cloudflare DNS > Settings > DNSSEC > Activate.

   Once the domain is properly activated on Cloudflare, for to SSL/TLS > Choose **Full** or **Full (Strict)** Encryption if your origin has SSL. Also enable **Always use HTTPS**.

   **WARNING : YOUR WEBSITE FRONTEND OR OTHER MIGHT FAIL BECAUSE OF CLOUDFLARE PROXY**
   If that's the case, you will need to troubleshoot this as it depends of your setup.

2. Back to the Pi Download the setup script\
   `bash <(curl -s https://raw.githubusercontent.com/TheComputationalMonkeys/HI-pfs/main/scripts/bootstrap.sh)`



