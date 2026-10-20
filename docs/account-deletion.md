# Permanent account deletion and role-save confirmation

ADMIN can delete another account from ผู้ใช้และสิทธิ์. The checkbox and final confirmation explain that the original account cannot be restored and that the person may register again. No account is deleted merely by deploying this feature.

The trusted backend prepares deletion in a transaction: revoke actual staff Auth sessions, remove application sessions/roles/LINE and staff identity mappings/link codes/team links/report recipient mappings, revoke assignments and invitations created by that user, and hide the old principal. For staff, the backend then calls Supabase Auth Admin DELETE with `should_soft_delete:false`. Finalization checks the Auth user no longer exists before reporting success.

Auth deletion and application database changes cannot share a transaction. A backend-only deletion ledger makes this retryable: on failure the account remains inaccessible, its old Auth UID cannot auto-create a new app identity, and ADMIN sees a retry entry under บัญชีที่ปิดไว้ก่อนหน้า / ลบค้าง. The ledger clears its temporary Auth UID on success. It does not store an email, LINE subject or credentials. The backend accepts an already-deleted Auth user only for the explicit `user_not_found` 404 response. Storage-owned objects or other Auth constraints can block deletion; the system does not silently remove business files to work around such an error.

After successful deletion, a new Auth account with the same email or a fresh LINE registration for the same subject receives a new principal with no inherited roles, assignments, sessions or links. It obtains new access via an active invitation. The original account cannot be restored through old management RPCs. The previous archive/restore HTTP actions are no longer exposed. Older archived accounts may be permanently deleted from the legacy/retry section.

Job orders, B/L status and audit events retain their foreign-key actor ID, labelled บัญชีที่ลบแล้ว. This anonymous reference is not a recoverable account or login identity. Deletion does not delete business work or rewrite status history. Historical audit payloads remain business records.

Role saves now return a server-side readback of the target's ID, name, state and roles after the write. The UI displays those saved values in a visible status message and clears its confirmation checkbox. A failed write or failed readback never displays a success notice.

Verification: Node tests cover mapped Auth IDs (client-supplied IDs ignored), hard-delete requests, failure/retry handling, LINE-only deletion and backend denial. `tests/account-deletion.sql` creates disposable Auth and app fixtures inside a rolled-back transaction, checks new registration, blocked old identities, preserved jobs, denied self/nonadmin deletion, disabled restoration and actual role-change readback. No existing user is deleted or changed by these tests.

