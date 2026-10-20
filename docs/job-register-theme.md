# Job register, permanent deletion and yellow theme

The job register provides literal, case-insensitive server search across Job number, B/L/HBL and Consignee, with an explicit field selector. All-fields search also includes Job OPR and Destination. Status and inclusive Job Date boundaries combine with the same B/L predicate. Sorts include Job Date, Job number, contact name and Consignee; page sizes are 10/25/50.

The summary distinguishes matching Job count from matching B/L count across **all** pages, and separately displays the current page's counts. Only matching B/L rows appear in the register; opening a Job still displays its full detail. A Job can have other B/Ls that do not match the current filter. Stale responses are ignored after filter changes; old counts are hidden while the new query is pending. Pagination has stable ID tie-breaks and returns to a valid page after deletion.

Search is backend-only and preserves role/state/RLS checks and the MESS today-plus-unfinished-earlier date rules. No browser-side full-database filtering or counting is used. The new service-role-only SECURITY INVOKER RPCs are `impjo_search_jobs` and `impjo_delete_job`.

STAFF ADMIN/OPERATOR can permanently delete one Job at a time, from its detail or the register's expandable management section. Confirmation explicitly includes **the entire Job**, all B/Ls, assignments and related audit/chat history, even B/Ls hidden by a filter. The transaction checks the Job version and locks the Job and B/Ls. It deletes the underlying rows rather than archiving them. Old chat confirmations and QR links cannot restore or update the deleted Job. The previous archive/restore HTTP actions are removed. Previously archived Jobs may be explicitly deleted from their legacy section; no existing Jobs are automatically purged by deployment.

Matching report-outbox business snapshots are cleared and marked CANCELLED while retaining a content-free deduplication slot. A deletion audit records only actor and aggregate counts, without Job ID, Job number or a snapshot. Other Jobs and their histories are unaffected. Catalog master data such as a shared contact remains separate. Previously delivered LINE messages and platform backups are outside live application deletion.

The visual palette uses yellow as the main brand color, white work surfaces, black text/navigation emphasis and red destructive/error actions. Shared pages and LINE MESS cards follow the palette. Thai navigation, headings, search guidance and form labels use formal operational wording. The responsive register keeps filters in two columns on narrow screens and allows horizontal table scrolling for long B/L and Consignee values.

Verification: TypeScript, Vite production build, 66 Node tests and SQL rollback tests. SQL checks all-page totals, exact B/L filtering, date sorting/pagination, inclusive dates, MESS scope, anonymous/pending restrictions, stale and unauthorized deletion denial, complete deletion and unchanged unrelated Jobs. No real Job is deleted during QA.

