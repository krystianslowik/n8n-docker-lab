#!/usr/bin/env bash
# Builds the hostable copy of the lesson page into site-dist/.
#
#   ./tools/build-site.sh
#
# The output is plain static files: HTML, CSS, JS, one JSON file and one PNG. Any static host
# can serve it; there is no server side. The live panel in the hosted copy only
# contacts a participant's own lab at http://localhost:5691 when they open it.
#
# Does not deploy anything. See DEPLOY.md for that.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=site-dist
[ -f console/public/data/evidence.json ] || {
	echo "console/public/data/evidence.json is missing. Run ./tools/rehearse.sh first." >&2
	exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT/assets" "$OUT/data"
cp console/public/index.html console/public/styles.css console/public/commands.js console/public/app.js "$OUT/"
cp console/public/data/evidence.json "$OUT/data/"
cp assets/hero.png "$OUT/assets/"

# Headers for hosts that read a _headers file (Cloudflare Pages, Netlify).
# Others ignore it.
cat >"$OUT/_headers" <<'EOF'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  X-Frame-Options: DENY
/data/*
  Cache-Control: no-cache
EOF

# Every file the page references must exist in the build.
missing=0
for ref in $(grep -oE '(src|href)="[^"#:]+"' "$OUT/index.html" | sed -E 's/^(src|href)="//; s/"$//' | sort -u); do
	[ -e "$OUT/$ref" ] || { echo "missing in build: $ref" >&2; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1

echo "Built $OUT/ ($(du -sh "$OUT" | cut -f1), $(find "$OUT" -type f | wc -l | tr -d ' ') files)"
find "$OUT" -type f | sort | sed 's/^/  /'
