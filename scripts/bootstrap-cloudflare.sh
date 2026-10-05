#!/usr/bin/env bash
# Creates the Cloudflare resources the API needs. Idempotent — safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="${DB_NAME:-notch}"
BUCKET="${BUCKET:-notch}"
ASSETS_DOMAIN="${ASSETS_DOMAIN:-assets.notchmetrics.com}"

cd "$ROOT/apps/api"
WRANGLER="pnpm exec wrangler"

echo "==> D1 database: $DB_NAME"
$WRANGLER d1 create "$DB_NAME" 2>&1 | sed 's/^/    /' || echo "    (already exists)"

echo "==> R2 bucket: $BUCKET"
$WRANGLER r2 bucket create "$BUCKET" 2>&1 | sed 's/^/    /' || echo "    (already exists)"

echo
echo "==> database_id for wrangler.jsonc"
$WRANGLER d1 list --json 2>/dev/null \
  | node -e "
      let raw = '';
      process.stdin.on('data', (c) => (raw += c));
      process.stdin.on('end', () => {
        const rows = JSON.parse(raw);
        const row = rows.find((r) => r.name === '$DB_NAME');
        console.log(row ? row.uuid : '(not found)');
      });
    " | sed 's/^/    /'

cat <<'NEXT'

Still to do by hand — neither can be done from the CLI:

  1. The R2 public domain. Dashboard → R2 → notch → Settings → Public access →
     Connect a domain, and attach assets.notchmetrics.com.

  2. The R2 *S3 API* token, which is not the same thing as the bucket binding.
     The binding reads and writes objects from inside the Worker; only an S3
     token can be used by the release workflow's `aws s3 cp`.
     Dashboard → R2 → Manage API tokens → Create, object read & write on the
     `notch` bucket. Then set, as repository secrets:

         R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY

  3. Worker secrets, set once and surviving every deploy:

         wrangler secret put BETTER_AUTH_SECRET     --env production
         wrangler secret put INTEGRATION_KEK_V1     --env production
         wrangler secret put DODOPAYMENT_API_KEY    --env production
         wrangler secret put DODOPAYMENT_WEBHOOK_SECRET --env production

     INTEGRATION_KEK_V1 must be 32 random bytes, base64:  openssl rand -base64 32
     Never delete a KEK while any row still names it — those integrations
     become permanently unreadable and there is no backup of a user's API key.
NEXT
