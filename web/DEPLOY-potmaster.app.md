# Deploy potmaster.app

Use these URLs in **App Store Connect**:

| Purpose | URL |
|---------|-----|
| Privacy Policy | https://potmaster.app/privacy/ |
| Support | https://potmaster.app/support/ |
| Marketing (optional) | https://potmaster.app/ |

The site is the static `web/` folder in this repo.

## Fastest: one-command deploy (Vercel API)

1. Create a token at https://vercel.com/account/tokens
2. Save it locally (gitignored):

```bash
echo 'VERCEL_TOKEN=your_token_here' > web/.env.vercel
```

3. Deploy:

```bash
python3 web/deploy_vercel.py
```

4. Add the DNS records the script prints at your domain registrar.

---

## Option A — Cloudflare Pages (recommended if DNS is on Cloudflare)

1. Push this repo to GitHub.
2. In [Cloudflare Dashboard](https://dash.cloudflare.com) → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**.
3. Select the repo. Set **Build output directory** to `web` (no build command).
4. Deploy. You get a `*.pages.dev` URL.
5. **Custom domains** → add `potmaster.app` and `www.potmaster.app`.
6. Cloudflare sets DNS automatically if the domain is on Cloudflare.

Wait a few minutes, then check:

- https://potmaster.app/privacy/
- https://potmaster.app/support/

---

## Option B — Vercel

1. Push this repo to GitHub (if it is not already).
2. Go to [vercel.com](https://vercel.com) → **Add New… → Project**.
3. **Import** your PokerLeader Git repository.
4. Configure the project:
   - **Framework Preset:** Other
   - **Root Directory:** `web` (click Edit → set to `web`)
   - **Build Command:** leave empty
   - **Output Directory:** leave as `.` (because root is already `web`)
5. Click **Deploy**. Vercel gives you a URL like `poker-leader.vercel.app`.
6. Check the preview:
   - `https://YOUR-PROJECT.vercel.app/privacy/`
   - `https://YOUR-PROJECT.vercel.app/support/`
7. **Add your domain:** Project → **Settings → Domains** → add `potmaster.app` and `www.potmaster.app`.
8. Vercel shows DNS records. At your domain registrar (where you bought potmaster.app), add what Vercel asks for. Usually:
   - **A record** for `@` → `76.76.21.21`
   - **CNAME** for `www` → `cname.vercel-dns.com`
   - If DNS is on Cloudflare, use the same values; turn **Proxy off** (DNS only / grey cloud) at first if SSL fails.
9. Wait for Vercel to show **Valid Configuration** (often 5–30 minutes).
10. Use in App Store Connect:
    - Privacy: `https://potmaster.app/privacy/`
    - Support: `https://potmaster.app/support/`

`web/vercel.json` is already in the repo for trailing slashes on `/privacy/` and `/support/`.

**CLI alternative** (from your machine):

```bash
npm i -g vercel
cd web
vercel login
vercel --prod
vercel domains add potmaster.app
```

Then add the DNS records Vercel prints in your registrar.

---

## Option C — Netlify

1. Push repo to GitHub.
2. [Netlify](https://app.netlify.com) → **Add new site** → **Import from Git**.
3. **Base directory:** `web`  
   **Publish directory:** `.` (or leave base as repo root and set publish to `web`)
4. Deploy → **Domain management** → add `potmaster.app`.
5. At your domain registrar, point DNS to Netlify (A/CNAME records Netlify shows you).

`netlify.toml` in `web/` handles `/privacy` → `/privacy/` redirects.

---

## Option D — GitHub Pages + custom domain

1. Repo → **Settings → Pages** → deploy from branch `main`, folder **`/web`**.
2. **Custom domain:** `potmaster.app` (GitHub uses the `CNAME` file in `web/`).
3. At your registrar, add the DNS records GitHub shows (usually `A` records + `CNAME` for `www`).

---

## Email: support@potmaster.app

App Store and the privacy page reference **support@potmaster.app**. Set that up separately:

- **Cloudflare Email Routing** (free): forward `support@` to your personal inbox.
- Or Google Workspace / Proton / similar if you want a real mailbox.

Until email works, forwards to your personal address are fine for v1.

---

## Local preview

```bash
cd web
python3 -m http.server 8080
```

Open http://localhost:8080/privacy/ and http://localhost:8080/support/
