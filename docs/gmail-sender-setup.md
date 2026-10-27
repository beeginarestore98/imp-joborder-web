# Gmail sender setup

Run the following only in Supabase Dashboard > Project imp-joborder-pilot/IMP Job Order (pqnqgwkivoiikyisydul) > Edge Functions > Secrets. Do not put passwords in GitHub, source files, VITE_* or chat.

- DOCUMENT_FROM_EMAIL: the owner's selected Gmail sender address.
- GMAIL_APP_PASSWORD: the dedicated 16-letter Google App Password, without spaces.

The owner must sign into the selected Google account, enable 2-Step Verification if needed, and create the App Password themselves at https://myaccount.google.com/apppasswords (suggested label IMP Job Order). The app password permits persistent account access, so keep it in backend secrets only and revoke it from Google when removing this integration. Do not disable 2-Step Verification or account security protections.

After saving both secrets, ADMIN selects a Contact Name and owner recipient email in People. First verify the SMTP connection and send one synthetic PDF to a recipient explicitly approved by the owner. Confirm the Gmail Sent folder and recipient inbox; an ACCEPTED API result alone is not delivery confirmation. No real job document should be used for the setup test.

No Resend account, custom DNS domain, Teams, university Entra permission or Power Automate Flow is required by this transport. Actual SMTP outbound port 465 availability must still be tested on the deployed function; ports 25 and 587 are prohibited by Supabase.
