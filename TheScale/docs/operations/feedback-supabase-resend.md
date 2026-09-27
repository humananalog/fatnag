# Feedback + Resend (FATNAG)

Consumer feedback POSTs to Supabase Edge Function `submit-feedback` on project `qtopujfrhfdzcngomoel`.

## Flow

```
iOS FeedbackSheetView / CoachReplyFeedbackSheet
  → Authorization: Bearer <anon key>
  → POST …/functions/v1/submit-feedback
  → validate → insert public.app_feedback (service role)
  → Resend → dev@humananalog.ai
  → 200 { ok, id, email_sent }
```

Coach reply votes use `source=coach_reply` with `rating` (`up`/`down`), plus
`live_model`, `on_device_model`, `reply_excerpt`, and `turn_id`.

## Secrets (never in git / IPA)

| Secret | Where |
|--------|--------|
| `RESEND_API_KEY` | Supabase Edge Function secrets |
| `RESEND_FROM` | Must be `Name <email@domain>` (e.g. `FATNAG Feedback <feedback@inbound.humananalog.ai>`). Bare/invalid `from` → Resend 422; insert still succeeds with `email_sent: false`. |
| `FEEDBACK_TO` | Optional; default `dev@humananalog.ai` |
| Service role | Auto in Edge runtime only |

Verified 2026-09-27: `source=coach_reply` insert + Resend email OK after correcting `RESEND_FROM`.

## Local / Debug without Resend

Inserts still succeed if `RESEND_API_KEY` is missing (`email_sent: false`). UI shows thank-you either way. Offline → error line, no crash.

## Source in repo

- Migration: `TheScale/supabase/migrations/20260927000000_create_app_feedback.sql`
- Function: `TheScale/supabase/functions/submit-feedback/index.ts`
- Client: `ScaleFeedbackConfig` / `ScaleFeedbackService` / `FeedbackSheetView`

Operator checklist: Agent Store `docs/feedback-rating-sandbox-handoff.md`.
