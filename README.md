# IMP Job Order — live application

React/TypeScript/Vite frontend + Cloudflare Pages Functions gateway + Supabase Edge Function backend + PostgreSQL authorization.

No mock records or mock login. All job/search/dashboard/assignment/status/audit requests use the backend. New accounts start pending, except the specifically approved first ADMIN after verified email ownership. Existing tables are unchanged.

## Runtime

Cloudflare Production Secret: IMPJO_GATEWAY_SECRET. The same secret must be stored in Supabase Edge Secrets. Do not commit credentials or .dev.vars. Supabase backend automatically receives its own SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and SUPABASE_ANON_KEY; no privileged database key is placed in Cloudflare or the browser.

Supabase Edge Secrets: IMPJO_GATEWAY_SECRET, LINE_LOGIN_CHANNEL_SECRET. Messaging API secrets: LINE_MESSAGING_CHANNEL_SECRET and LINE_MESSAGING_CHANNEL_ACCESS_TOKEN. Owner authorized activation on 2026-10-20; both are stored only in Supabase Edge Secrets.

LINE Login Channel 2012071986; Provider 2005629037; linked OA @110deiyl. Callback https://imp-joborder-web.pages.dev/api/line/callback. LIFF 2012071986-ymuhMXOT points to /portal. LINE Login uses authorization code + PKCE + state + nonce on server. LINE and staff credentials are kept in Secure HttpOnly cookies, never app localStorage. Login sessions require the user's verified identity; pending users cannot see jobs.

## Commands

npm ci
npm run build
node --test tests/backend.test.mjs

Build checks frontend, gateway and backend TypeScript. Cloudflare builds main with npm run build and output dist. Source backend is server/backend.ts; deploy it together with edge/index.ts (renamed backend.ts relative to index.ts) as Supabase function impjo-api. The function validates the gateway secret before invoking application code; JWT gateway verification is disabled because this endpoint supports its own authentication and LINE webhooks.

## Database

database/setup.sql is a one-time setup record, not an idempotent rerun. The bootstrap email is a placeholder in source: substitute only the owner-approved ADMIN email before first setup. This setup has already been applied to the approved project. Do not rerun it or silently overwrite existing tables.

Apply order for a fresh approved installation: setup.sql, staff-session.sql, then auth-bridge.sql. These migrations are already applied in production. The non-exposed impjo_private schema contains narrowly scoped SECURITY DEFINER helpers for verified staff identity and active Auth sessions. Only service_role may execute them; the backend has no broad read grant on auth.users or auth.sessions.

All impjo_* tables have RLS and no anon/authenticated grants. SECURITY INVOKER RPCs are service_role-only. Backend validates a staff token with Supabase Auth or resolves a hashed opaque LINE session, then SQL rechecks current approval, role and assignment on every operation. Audit and business writes share transactions.

Operator/Admin use staff email/password. Staff registration requires email confirmation; confirm the project email-verification setting before onboarding. LINE identities are separate internal principals and never receive fake email or OPERATOR accounts. ADMIN must compare a user's UUID with the person directly before approving; display name alone is insufficient.

Database authorization tests in tests/authorization.sql run in a transaction and roll back every test row. Sequence gaps may occur because PostgreSQL sequences are not transactional. No demonstration jobs are imported.

No real business data can be publicly read. If a secret or backend is unavailable, the API fails closed. Staff sessions expire after at most one hour and require login again; LINE sessions expire after eight hours or immediately when revoked. Approving/changing a user's role revokes their old LINE sessions and assignments, so they must sign in again and be reassigned.

Current initial limits: 50 B/L per job, 10 jobs per list page, 50 users/events per page. Assignment picker currently shows the most recent 50 users. QR codes and browser printing are implemented for authorized Job Detail pages. QR links require login and object authorization; they are not public access tokens. General job editing and exports are not yet enabled. Never claim these features work until implemented and verified.


## LINE OA chat

Webhook: https://imp-joborder-web.pages.dev/api/line/webhook. Rich Menu sends MESS / OPERATOR. Messaging credentials remain only in Supabase Edge Secrets.

MESS now lists assigned IN_PROGRESS B/L in private chat. Select a B/L, propose COMPLETED or send ISSUE details, then tap the confirmation within 10 minutes. Only the sender mapped from a valid LINE-signed webhook may act. Every request checks current approved MESS role; detail and status calls recheck current assignment through impjo_api. No role is granted by a code. Group chats cannot read job data. Issue details are required and capped at 2000 characters. Lists use server pagination/search (MESS 2, or MESS followed by a B/L or job number).

Confirmation proposals are recorded as CHAT_PROPOSE_* audit events. They do not change a business status. Confirmation is bound to the audit actor and expires after 10 minutes; status and assignment are read again. Replayed confirmations do not repeat the status write or its audit. Actual writes use the existing atomic impjo_api status transaction. No schema or RLS changes were needed.

OPERATOR remains a protected web form with staff email login, as the owner requested. Creating jobs in chat is not enabled. The website polls visible data every 15 seconds and refreshes on focus; it shares the same Supabase records as the bot. This is polling, not a Realtime subscription.

Tests: node --test tests/backend.test.mjs tests/mess-chat.test.mjs (19 pass). Covers unapproved/group access, issue detail requirement, proposal vs actual write, expiry, replay, revoked assignment and empty PostgREST write responses. Isolated SYSTEM TEST job IMP-2026-0000005 was prepared in IN_PROGRESS with explicit TEST_FIXTURE_PREPARED audit events for real chat verification; it is not a real freight handover.

When a MESS user selects Report Issue, CHAT_EXPECT_ISSUE records the selected B/L for up to 10 minutes. The next plain text message (e.g. นัดวันใหม่) is treated as issue details and produces a confirmation proposal. MESS, another B/L selection or CANCEL/ยกเลิก closes that input context. Approval, role and assignment checks still apply to every request. Confirmation is mandatory before a status write. No new schema was introduced.

## QR scanning

Rich Menu now has MESS, OPERATOR and SCAN QR. SCAN QR opens https://imp-joborder-web.pages.dev/scan. Approved users may explicitly start the camera or select a QR image. jsqr 1.4.0 decodes images locally; no camera/photo is uploaded. Only canonical HTTPS production /jobs/<UUID> links are accepted; arbitrary origins, credentials and non-job routes are rejected. Existing job detail backend checks remain authoritative, so scanning never grants an assignment. My Jobs opens /jobs with server-filtered access. LINE login has an allowlisted /scan return cookie; arbitrary redirect destinations are rejected.

Permissions-Policy allows same-origin camera only; microphone and geolocation remain disabled. CSP permits local blob images/media needed for decoding. No camera prompt occurs until the user presses Start Camera. Image decoding on the live site verified opening test job IMP-2026-0000006. Production build and 21 tests passed. Physical mobile camera/LINE permission flow still needs owner device verification.

## OPERATOR entry from Rich Menu

Owner chose to keep staff creation in a web form inside LINE and declined identity-linking tables. OPERATOR Rich Menu is now a direct URI to /operator. Approved ADMIN/OPERATOR staff see Create immediately; guests see email login and return to /operator after login. An existing LINE session shows an explicit Switch to staff account button, then the same login/form flow. No automatic role elevation or LINE/staff mapping is created. Backend create permissions are unchanged. Bot OPERATOR text also links to /operator. Production form route and active menu URI verified.

## Explicit Job Date

Applied database/job-date.sql. job_date is a separate DATE business field, required for new jobs. created_at remains the immutable recording timestamp. The owner chose to assign all existing dates manually: legacy job_date stays NULL, with no inferred backfill. ADMIN/OPERATOR may set dates on Job Detail; changes are audited. Form, list, detail and print use Job Date, and detail separately labels recorded time.

MESS current list is filtered in SQL: all assigned jobs dated today in Asia/Bangkok, plus unfinished assigned B/L dated before today. Future jobs, undated legacy jobs and completed older B/L are excluded. Current filtering is forced for MESS list requests, regardless of client-supplied filters. Chat buttons recheck the date window. Run tests/job-date.sql and tests/authorization.sql under service_role; fixtures roll back. Build and 22 Node tests pass.


## Team access and LINE handover
Approved ADMIN, OPERATOR and OUTSOURCE can read all job/B/L data. MESS reads assigned current work only. Account/assignment administration stays ADMIN-only; OUTSOURCE status writes still require its assignment.

New staff registrations appear in People before email confirmation. ADMIN verifies the person and explicitly activates email and role through the existing approval form. This uses server-side Auth Admin confirmation for that mapped app account only; global email confirmation remains enabled.

OPERATOR: sign into LINE Portal once, then sign into the staff website, open /line-link, generate a private one-use code (10 minutes), send the complete LINK message to OA, and ask ADMIN to approve the mapping in People. Type OPERATOR in OA, select a B/L, and confirm handover. OUTSOURCE types OUTSOURCE and selects assigned pending B/L. Both use the existing PENDING_HANDOVER -> IN_PROGRESS transition. New proposals expire in 10 minutes; identity, role, assignment and status are checked again on confirmation. Role/approval changes revoke staff LINE links.

Apply database/team-line.sql and database/outsource-job-visibility.sql once after prior migrations; these have already been applied to the live project. RLS and backend-only grants protect link tables. Raw linking codes and channel secrets are never stored in source or browser builds. Audit events identify the mapped acting principal.

Validation: production build, 31 Node tests, team-line SQL tests and existing authorization/operator-handover/job-date SQL regressions passed with transaction fixtures rolled back. Physical LINE account linking/handover requires the account owner to send the command and ADMIN to approve that actual account.
