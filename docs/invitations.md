# Reusable invitations

ADMIN opens **ผู้ใช้และสิทธิ์ → เชิญด้วยลิงก์ / QR Code**, chooses an identity type and role, and creates an invitation. Share the generated link or download its QR immediately: the raw bearer token is displayed only at creation. It cannot be recovered from the database. Create a replacement and revoke the old invitation if lost.

- Invitations are reusable by multiple people, have no automatic expiry, and remain available until ADMIN revokes them. An invitation also stops working if its creator is disabled, archived, or loses ADMIN.
- LINE invitations allow MESS, OUTSOURCE, or OPERATOR. Email invitations allow OPERATOR or ADMIN. Every holder who authenticates can obtain that invitation's preset role. Keep links within the intended team.
- Each recipient opens the link/QR, authenticates their own LINE or confirmed email account, and presses **รับคำเชิญและเข้าใช้งาน**. New/PENDING accounts are approved immediately in one transaction. Email verification is still required to establish email ownership; individual ADMIN approval is not required.
- Existing approved roles are never changed by visiting another invitation. Disabled, rejected and archived accounts cannot reactivate themselves. ADMIN can still manage existing accounts separately.
- Revoking an invitation blocks new redemptions, including old copies of its QR. Previously enrolled accounts retain their roles; suspend those accounts separately if necessary.
- Staff-to-LINE linking remains a separate, authenticated process. Invitations do not silently link two identities.

## Security and verification

Tokens are 256-bit random values. Only SHA-256 hashes are stored. Raw tokens use a URL fragment, are captured into same-tab sessionStorage and immediately removed from the address bar; they do not enter URL queries, server access logs, referrers, audit records or Git. Only the new-link response returns a raw token. API responses are no-store. After redemption the browser removes its stored token.

The trusted gateway resolves the actor from an existing session and never forwards a client-supplied actor, role or kind on redemption. SQL rechecks creator status, invitation revocation, recipient state, identity kind and existing roles. Row locks serialize redemption and revocation. Unique invitation/person keys make repeat redemption idempotent without duplicate audit. Invitation tables use RLS with no client grants; the SECURITY INVOKER RPC is executable only by service_role.

LINE OAuth's return path explicitly allows only `/portal`, `/scan` and `/invite`. It never carries the invitation bearer. Email confirmation returns to the existing `/login` route, and the original tab resumes its saved invitation after password login. If an external browser opens, reopen the original invitation there.

No new environment variables or secrets are required. `database/invitations.sql` is additive; existing job tables and permissions are unchanged. `tests/invitations.sql` uses rollback fixtures; Node tests cover gateway actor binding, hashed forwarding, authentication, unavailable tokens and redirect allowlisting.

