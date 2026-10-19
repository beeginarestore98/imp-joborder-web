# IMP Job Order — Phase A working source

React + TypeScript + Vite + Tailwind CSS + React Router. Thai logistics dashboard, responsive sidebar, job list with search/filter/pagination, dynamic multi-B/L form, job detail, locked assignment UI, sample audit log, LINE portal, login and access screens.

Integrated into the existing `beeginarestore98/imp-joborder-web` repository after inspection of main at 67e63ab (README-only initial commit). The repository was Public at inspection. No duplicate repository was created.

## Run

`npm install` then `npm run dev`. Production: `npm run build`; preview: `npm run preview`.

## Phase A boundaries

All records are explicitly fictional. Draft form submissions are in-memory only and reset on refresh. Drafts have no generated Job Number; production numbering belongs to the database. There is no fake login, account approval, assignment, status mutation, LINE connection, real audit recording, or database access. Login inputs and privileged actions are disabled. UI route visibility is not authorization.

## Cloudflare Pages

Use the existing GitHub repository after integration. Production branch `main`; framework Vite / React (Vite); build command `npm run build`; output `dist`. `public/_redirects` enables SPA route refresh. `_headers` sets static security headers. No Phase A environment variables or secrets required.

Before production delivery verify the Cloudflare GitHub App can access the correct existing repository, confirm successful deployment, open the actual public HTTPS URL, refresh `/jobs` and `/portal`, and verify mobile layout. A local build does not confirm deployment.

## Phase B configuration names (not yet used)

Browser: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_LIFF_ID`, and optionally a public backend base URL after architecture approval. Never put private credentials in `VITE_*`.

Server only: `LINE_LOGIN_CHANNEL_ID`, `LINE_LOGIN_CHANNEL_SECRET`, `LINE_MESSAGING_CHANNEL_SECRET`, `LINE_MESSAGING_CHANNEL_ACCESS_TOKEN`; Supabase server credentials only if required by the approved design, stored as backend secrets. Never expose service role keys, LINE secrets, access tokens, or ID tokens in static assets or logs.

Inspect the actual profiles, user_roles, job_orders, job_bls, job_assignments, job_events schema, RLS, and has_role / assign_job_bl / change_bl_status signatures before integration. No schema/RLS/function changes have been made. Map verified LINE issuer+subject to an approved internal identity and resolve Auth User IDs before assignment/event writes. Validate token audience/issuer/expiry on server and enforce role and assignment on every request. Require details for ISSUE_REPORTED. Never trust LINE display names or user IDs submitted by clients.

## LIFF handoff

After HTTPS deployment is verified, set the LIFF Endpoint URL to the final public URL plus `/portal` in the existing LINE Login channel. Add the issued LIFF ID to the Phase B configuration. Phase A portal remains a demonstration and cannot authenticate users. Add LIFF SDK and verified server login only after identity mapping and authorization are approved and tested.

