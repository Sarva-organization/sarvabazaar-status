#!/usr/bin/env bash
# Run the status page locally against this repo's .upptimerc.yml.
#
#   ./scripts/preview.sh          # http://localhost:3001
#   PORT=4000 ./scripts/preview.sh
#
# This is the same @upptime/status-page build the Static Site CI workflow
# deploys, so styling, footer text, favicon, nav and per-monitor descriptions
# all render exactly as they will in production.
#
# One caveat: the page pulls live monitor data (names, icons, uptime) from
# history/summary.json on the PUSHED repo via raw.githubusercontent.com, not
# from your working copy. So edits to `name:` / `icon:` in .upptimerc.yml only
# show up here after they've been pushed and the summary workflow has rerun.
# Everything the status-website block controls updates immediately.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
SITE_DIR="$REPO_ROOT/site"
PORT="${PORT:-3001}"

# pre-process.ts reads ../.upptimerc.yml, so the app has to live one level down.
if [ ! -d "$SITE_DIR/node_modules/sapper" ]; then
  echo "==> First run: installing @upptime/status-page into site/ (a few minutes)"
  mkdir -p "$SITE_DIR"
  cd "$SITE_DIR"
  [ -f package.json ] || npm init -y >/dev/null
  npm i @upptime/status-page --no-audit --no-fund --loglevel=error
  cp -r node_modules/@upptime/status-page/* .
  npm i --no-audit --no-fund --loglevel=error
else
  cd "$SITE_DIR"
fi

# Mirror what the deploy does: assets/ is copied over the built site root.
echo "==> Syncing assets/"
cp -r "$REPO_ROOT/assets/"* static/

# Regenerate src/data/config.json from .upptimerc.yml
echo "==> Reading .upptimerc.yml"
npx ts-node pre-process.ts

# pre-process derives config.path from `cname`, i.e. the production domain.
# The app uses it for every internal link AND for its error redirects, so a
# local run would send you to the live site the moment the GitHub API rate
# limits (60/hr unauthenticated) — silently showing you production instead of
# your changes. Point it at this server for the preview only; config.json is
# regenerated on every run and is inside the gitignored site/ directory.
#
# logoUrl and favicon are absolute (https://<cname>/...) on purpose: see the
# comment beside them in .upptimerc.yml. Left alone they would load from the
# live site during a preview, so they are pointed at this server too.
echo "==> Rewriting config.path -> http://localhost:$PORT (preview only)"
PORT="$PORT" node -e '
  const fs = require("fs"), f = "src/data/config.json";
  const c = JSON.parse(fs.readFileSync(f, "utf8"));
  const local = "http://localhost:" + process.env.PORT;
  const prod = c.path;
  c.path = local;
  const sw = c["status-website"] || {};
  for (const k of ["logoUrl", "favicon", "faviconSvg"]) {
    if (typeof sw[k] === "string" && sw[k].startsWith(prod)) {
      sw[k] = local + sw[k].slice(prod.length);
    }
  }
  fs.writeFileSync(f, JSON.stringify(c, null, 2));
'

echo "==> http://localhost:$PORT"
PORT="$PORT" npx sapper dev
