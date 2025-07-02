# HI-pfs
Your ipfs network as easy and cheap one can say Hi!

## Requirements


## Setup
### Scenario A: Use a subdomain from your existing domain (recommended)
1. Create a subdomain (eg. `ipfs.yourdomain.com`).
   
    If you own a domain already and want to keep things together, a subdomain might be a good choice to link your ipfs network to. Feel free to try other scenarios and share your steps with a pull so we can document it here and make it accessible for others.

   **CLOUDFLARE SETUP**
    - Go to [Cloudflare](https://www.cloudflare.com/) and create an account with a **FREE** plan (or more if you want).
    - Add your full domain name: `yourdomain.com` with an auto scan and check if all your DNS entries are there. Otherwise add the missing ones manually.
    - Follow the steps to change your DNS servers. It might vary from one domain provider to another.
    - Go to DNS tab, click Add Record:
      - Type: `NS`
      - Name: `ipfs` (this makes `ipfs.yourdomain.com`)
      - Content: `ipfs.ns.cloudflare.com` (Cloudflare name servers)
   
   **DOMAIN PROVIDER SETUP**
   These steps may vary depending on your domain provider:
   - Go to your DNS zone entries
   - Add an NS record for the subdomain:
      - Subdomain: `ipfs`
      - Type: `NS`
      - Target: Same Cloudflare name servers as above (eg. `ipfs.ns.cloudflare.com`)

This delegates `ipfs.yourdomain.com` to Cloudflare while keeping the rest of your domain on your domain provider.
Wait for Cloudflare to have propagated the changes and check that your website and emails are working. This may take more than 24H. Check the scheduled operations in your domain provider to make sure. If you have deactivated DNSSEC in your domain provider and would like to reactivate it, you can then do so by going to the panel of your domain on Cloudflare DNS > Settings > DNSSEC > Activate.

Once the domain is properly activated on Cloudflare, for to SSL/TLS > Choose **Full** or **Full (Strict)** Encryption if your origin has SSL. Also enable **Always use HTTPS**.


2. Create tunneling on your PI

   - download cloudlfared on your PI (check the Github URL, it could have changed)\
      `curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o cloudflared.deb`
   - install\
      `sudo dpkg -i cloudflared.deb`
   - check if installed. If you see a version number, you're good togo. Itherwise check links urls and potential updates on Cloudflared's github.\
      `cloudflared --version`
   - Login to your cloudflare account\
       `cloudflared tunnel login`


