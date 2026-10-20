# LINE OA operations cards

MESS, OPERATOR and OUTSOURCE replies use a consistent yellow, white, red and black Flex Message design. Thai instructions use formal operational wording. Commands still select a menu only; identity and every write are authorized by the existing backend and database.

Current B/L lists render a horizontally scrollable carousel, one card per B/L, with Job number, B/L number, Job Date, actual status and a three-stage tracker: รอส่งมอบ → ดำเนินการ → เสร็จสิ้น. A separate navigation card preserves the existing paginated workflow. No B/L is dropped from an authorized page and its postback IDs remain unchanged.

The tracker is a workflow-stage indicator, not an estimate of percentage complete. ISSUE_REPORTED highlights the operational stage red and explicitly states that the work is unfinished. Unknown statuses show no completed stage. Data comes from structured metadata populated by authorized database reads, never from parsing issue descriptions or user-supplied message text.

Detail and confirmation replies retain the actual current stage. A proposed target status is displayed separately and is applied only after the existing confirmation, current-role and concurrency checks pass. Success replies use the recorded new status. Completed work reopened by OPERATOR/OUTSOURCE shows its new actual stage on subsequent reads. Previously delivered chat cards remain historical snapshots; users should refresh the menu to see current data.

Yellow action boxes use black labels for contrast. Issue/confirmation actions use red with white labels. The renderer uses native Flex components and no remote images, fonts or tracking assets. Text fallback (`altText`) is bounded to 400 characters. Carousel length and payload size are bounded by the existing five-B/L pagination.

The Rich Menu artwork follows the same palette; MESS and OPERATOR remain text commands and QR retains the existing scan URL. There are no schema, RLS, identity mapping, environment-variable or secret changes.

Verification includes all prior authorization/confirmation tests and new cases covering the four statuses, truthful proposed/current state separation, per-B/L carousel actions and pagination, workflow-specific branding, bounded payloads and prevention of progress fabrication from free text.

References: https://developers.line.biz/en/docs/messaging-api/using-flex-messages/ and https://developers.line.biz/en/docs/messaging-api/flex-message-layout/.

