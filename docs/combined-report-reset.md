# Combined MESS report, PDF and OPERATOR reset

MESS chooses no problem or issue with reason, optionally captures/selects up to 10 image pages (5 MB total), previews the combined PDF, and confirms once. Backend validates the authenticated MESS, current recipient version and optimistic status. The transaction closes the B/L as COMPLETED and stores report_outcome/report_detail separately. It links an optional READY private PDF owned by the same actor and B/L to the unique status notification. A single Gmail message carries the report and optional PDF; issue messages use high priority and an important subject. SMTP acceptance is shown truthfully; it does not prove inbox delivery.

The linked PDF cannot be claimed by the standalone document sender. Status and document delivery outcomes share a lease. Missing PDF blocks SMTP. UNKNOWN delivery is not automatically resent.

OPERATOR can explicitly reset a B/L for new handover. Confirmation permanently removes old reports, document metadata, assignments and B/L events, retaining only minimal WORK_RESET audit. Storage object paths are server-selected. Pending cleanup persists until Storage deletion succeeds and is retryable; new updates/uploads are blocked during cleanup. Recent sends/uploads block reset. Job and B/L fields remain. Sent email cannot be recalled. OUTSOURCE/MESS cannot purge reports.

Validation: TypeScript/production build; 109 Node tests; all 25 SQL regression suites inside a rolled-back transaction including combined mail lease, completed issue result, reset authorization, purge and cleanup retry. Post-migration combined/status SQL checks also passed. No real jobs were reset and no email was sent during this work.
