# Job form catalogs and MESS cards

MESS workflow replies use LINE Flex bubbles with persistent buttons inside the message. Contact/B/L pagination, actor authorization and confirmation remain unchanged. Issue presets “แจ้งวันนัดใหม่” and “แก้ไขเอกสาร” populate the issue detail, then ask for confirmation. Custom details remain available. OPERATOR/OUTSOURCE issue workflows also offer these presets.

Supabase impjo_catalog stores CONTACT (name/phone), PURPOSE (requires_amount), and SHIPPING. Only approved STAFF ADMIN/OPERATOR may access its service-only RPC through authenticated backend sessions. RLS/default-deny and no public table/RPC grants remain. Contact changes affect the directory and newly selected forms; existing Job snapshots remain unchanged. Contact deletion is recoverable archival. Saving the same Contact name updates its phone/reactivates it rather than adding duplicates. Purpose names can be added with an optional amount requirement; existing requirements cannot be silently weakened by re-adding a name.

Job creation and editing share linked Contact fields, Purpose dropdown, add Contact/Purpose controls, and searchable Destination suggestions. Destination also accepts manually typed text for existing ports, agents or unlisted companies. Existing job Purpose values remain selectable during edit. Money is THB, stored as numeric(14,2), required for ตามใบมัดจำตู้ and ตามใบเสร็จ, validated server-side without rounding excess decimal places. It appears in Job detail and in numeric Excel column Q with two decimal places. The value is a Job amount, repeated per B/L in the existing one-row-per-B/L export; do not sum duplicate Job rows as separate amounts.

31 shipping/agency company names were verified from the BSAA ordinary members directory, retrieved 20 October 2026. This is an initial source-backed directory, not an exhaustive/live-scraped list of every company in Thailand. No third-party scripts, addresses or contact persons were imported.

- https://www.thaibsaa.com/index.php/members/members-directory/ordinary-members
- https://www.thaibsaa.com/index.php/members/members-directory/ordinary-members?start=20
- Flex structure: https://developers.line.biz/en/docs/messaging-api/flex-message-elements/

Migration order: form-catalog.sql, shipping-seed.sql after existing migrations. No new frontend or backend secrets required. Existing Contacts were initialized from the most recent phone in active Job snapshots without changing those jobs or guessing missing phone numbers.

Validation includes transactional tests/form-catalog.sql (contacts, immutable snapshots, decimal precision, create/edit/export, authorization), preset/card unit tests, TypeScript and production builds. Test fixtures are rolled back; real jobs/statuses are not changed during QA. New LINE Flex rendering must be checked in an approved MESS owner's LINE session.

