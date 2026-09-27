-- FATNAG consumer feedback (Human Analog).
-- Applied to project qtopujfrhfdzcngomoel (the-hive).
-- Inserts only via Edge Function service role.

CREATE TABLE IF NOT EXISTS public.app_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  app_version text,
  build text,
  platform text NOT NULL DEFAULT 'ios',
  locale text,
  category text NOT NULL CHECK (category IN ('bug', 'idea', 'praise')),
  message text NOT NULL CHECK (char_length(message) BETWEEN 1 AND 2000),
  contact text CHECK (contact IS NULL OR char_length(contact) <= 320),
  device_model text,
  plan_tier text,
  anonymous_user_id uuid NOT NULL,
  source text NOT NULL DEFAULT 'settings'
    CHECK (source IN ('settings', 'soft_ask', 'debug'))
);

COMMENT ON TABLE public.app_feedback IS
  'FATNAG consumer feedback. Written only by submit-feedback Edge Function (service role).';

CREATE INDEX IF NOT EXISTS app_feedback_created_at_idx
  ON public.app_feedback (created_at DESC);

CREATE INDEX IF NOT EXISTS app_feedback_anonymous_user_id_idx
  ON public.app_feedback (anonymous_user_id);

ALTER TABLE public.app_feedback ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.app_feedback FROM anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.app_feedback TO service_role;
