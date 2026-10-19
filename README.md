# IMP Job Order — live application

React/TypeScript/Vite frontend + Cloudflare Pages Functions gateway + Supabase Edge Function backend + PostgreSQL authorization.

No mock records or mock login. All job/search/dashboard/assignment/status/audit requests use the backend. New accounts start pending, except the specifically approved first ADMIN after verified email ownership. Existing tables are unchanged.

## Runtime

Cloudflare Production Secret: IMPJO_GATEWAY_SECRET. The same secret must be stored in Supabase Edge Secrets. Do not commit credentials or .dev.vars. Supabase backend automatically receives its own SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and SUPABASE_ANON_KEY; no privileged database key is placed in Cloudflare or the browser.

Supabase Edge Secrets: IMPJO_GATEWAY_SECRET, LINE_LOGIN_CHANNEL_SECRET. Optional Messaging API secrets: LINE_MESSAGING_CHANNEL_SECRET and LINE_MESSAGING_CHANNEL_ACCESS_TOKEN. Messaging remains disabled until the owner authorizes token creation.

LINE Login Channel 2012071986; Provider 2005629037; linked OA @110deiyl. Callback https://imp-joborder-web.pages.dev/api/line/callback. LIFF 2012071986-ymuhMXOT points to /portal. LINE Login uses authorization code + PKCE + state + nonce on server. LINE and staff credentials are kept in Secure HttpOnly cookies, never app localStorage. Login sessions require the user's verified identity; pending users cannot see jobs.

## Commands

npm ci
npm run build
node --test tests/backend.test.mjs

Build checks frontend, gateway and backend TypeScript. Cloudflare builds main with npm run build and output dist. Source backend is server/backend.ts; deploy it together with edge/index.ts (renamed backend.ts relative to index.ts) as Supabase function impjo-api. The function validates the gateway secret before invoking application code; JWT gateway verification is disabled because this endpoint supports its own authentication and LINE webhooks.

## Database

database/setup.sql is a one-time setup record, not an idempotent rerun. The bootstrap email is a placeholder in source: substitute only the owner-approved ADMIN email before first setup. This setup has already been applied to the approved project. Do not rerun it or silently overwrite existing tables.

All impjo_* tables have RLS and no anon/authenticated grants. SECURITY INVOKER RPCs are service_role-only. Backend validates a staff token with Supabase Auth or resolves a hashed opaque LINE session, then SQL rechecks current approval, role and assignment on every operation. Audit and business writes share transactions.

Operator/Admin use staff email/password. Staff registration requires email confirmation; confirm the project email-verification setting before onboarding. LINE identities are separate internal principals and never receive fake email or OPERATOR accounts. ADMIN must compare a user's UUID with the person directly before approving; display name alone is insufficient.

Database authorization tests in tests/authorization.sql run in a transaction and roll back every test row. Sequence gaps may occur because PostgreSQL sequences are not transactional. No demonstration jobs are imported.

No real business data can be publicly read. If a secret or backend is unavailable, the API fails closed. Staff sessions expire after at most one hour and require login again; LINE sessions expire after eight hours or immediately when revoked. Approving/changing a user's role revokes their old LINE sessions and assignments, so they must sign in again and be reassigned.

Current initial limits: 50 B/L per job, 10 jobs per list page, 50 users/events per page. Assignment picker currently shows the most recent 50 users. QR codes and browser printing are implemented for authorized Job Detail pages. QR links require login and object authorization; they are not public access tokens. General job editing, exports and Messaging API automation are not yet enabled. Never claim these features work until implemented and verified.

