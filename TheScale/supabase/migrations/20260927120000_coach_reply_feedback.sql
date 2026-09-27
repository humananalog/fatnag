-- Coach reply thumbs up/down (+ model / excerpt metadata).

ALTER TABLE public.app_feedback DROP CONSTRAINT IF EXISTS app_feedback_source_check;

ALTER TABLE public.app_feedback
  ADD CONSTRAINT app_feedback_source_check
  CHECK (source IN ('settings', 'soft_ask', 'debug', 'coach_reply'));

ALTER TABLE public.app_feedback
  ADD COLUMN IF NOT EXISTS rating text
    CHECK (rating IS NULL OR rating IN ('up', 'down'));

ALTER TABLE public.app_feedback
  ADD COLUMN IF NOT EXISTS live_model text;

ALTER TABLE public.app_feedback
  ADD COLUMN IF NOT EXISTS on_device_model text;

ALTER TABLE public.app_feedback
  ADD COLUMN IF NOT EXISTS reply_excerpt text
    CHECK (reply_excerpt IS NULL OR char_length(reply_excerpt) <= 800);

ALTER TABLE public.app_feedback
  ADD COLUMN IF NOT EXISTS turn_id uuid;

COMMENT ON COLUMN public.app_feedback.rating IS
  'Coach reply vote: up | down. Null for Settings / soft-ask feedback.';
COMMENT ON COLUMN public.app_feedback.live_model IS
  'Keel / Grok model id when feedback is about a live Coach reply.';
COMMENT ON COLUMN public.app_feedback.on_device_model IS
  'On-device polish label (Apple Intelligence / local GGUF).';
