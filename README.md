# HI-pfs
Your ipfs network as easy and cheap one can say Hi!

## Requirements


## Setup
1. Create a subdomain (recommended).\
    If you own a domain already ans want to keep things together, a subdomain might be a good choice to link your ipfs network to. Feel free to try other scenarios and share your steps so we can document it here and make it accessible for others.
    - Go to CLoudflare and create an account with a free plan
    - Add your full domain: `example.com`
    - Skip changing name servers for now
    - Go to DNS tab, click Add Record:
      - Type: NS
      - Name: ipfs (this makes ipfs.example.com)
      - Content: Cloudflare name servers (e.g., ipfs.ns.cloudflare.com)

   These steps may vary dependig on your domain provider:
   Let's say your domain is `example.com`
   - Add an NS record for the subdomain:
      - Subdomain: ipfs
      - Type: NS
      - Target: Same Cloudflare name servers as above
  This delegates `ipfs.example.com` to Cloudflare while keeping the rest of your domain on your domain provider.




1. download cloudlfared on your Pi\
  `curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o cloudflared.deb`
2. install\
  `sudo dpkg -i cloudflared.deb`
3. check if installed. If you see a version number, you're good togo. Itherwise check links urls and potential updates on Cloudflared's github.\
  `cloudflared --version`
4. Login to your cloudflare account\
   `cloudflared tunnel login`


