# Feedback + Resend (FATNAG)

Consumer feedback POSTs to Supabase Edge Function `submit-feedback` on project `qtopujfrhfdzcngomoel`.

## Flow

```
iOS FeedbackSheetView
  → Authorization: Bearer <anon key>
  → POST …/functions/v1/submit-feedback
  → validate → insert public.app_feedback (service role)
  → Resend → dev@humananalog.ai
  → 200 { ok, id, email_sent }
```

## Secrets (never in git / IPA)

| Secret | Where |
|--------|--------|
| `RESEND_API_KEY` | Supabase Edge Function secrets |
| `RESEND_FROM` | Optional; default `FATNAG Feedback <feedback@inbound.humananalog.ai>` |
| `FEEDBACK_TO` | Optional; default `dev@humananalog.ai` |
| Service role | Auto in Edge runtime only |

## Local / Debug without Resend

Inserts still succeed if `RESEND_API_KEY` is missing (`email_sent: false`). UI shows thank-you either way. Offline → error line, no crash.

## Source in repo

- Migration: `TheScale/supabase/migrations/20260927000000_create_app_feedback.sql`
- Function: `TheScale/supabase/functions/submit-feedback/index.ts`
- Client: `ScaleFeedbackConfig` / `ScaleFeedbackService` / `FeedbackSheetView`

Operator checklist: Agent Store `docs/feedback-rating-sandbox-handoff.md`.
