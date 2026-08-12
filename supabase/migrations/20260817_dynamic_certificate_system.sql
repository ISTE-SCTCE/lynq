-- ============================================================
-- Migration: Dynamic Certificate System Schema
-- ============================================================

-- 1. Certificate Templates Table
CREATE TABLE IF NOT EXISTS public.certificate_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id BIGINT REFERENCES public.events(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  template_file_url TEXT NOT NULL,
  template_format TEXT NOT NULL DEFAULT 'image', -- 'image' | 'html' | 'svg' | 'pdf'
  natural_width NUMERIC DEFAULT 2000,
  natural_height NUMERIC DEFAULT 1414,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Certificate Template Fields Table
CREATE TABLE IF NOT EXISTS public.certificate_template_fields (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id UUID NOT NULL REFERENCES public.certificate_templates(id) ON DELETE CASCADE,
  field_key TEXT NOT NULL,          -- e.g. 'student_name'
  tag TEXT NOT NULL,                -- e.g. '{{STUDENT_NAME}}'
  x NUMERIC NOT NULL DEFAULT 0,
  y NUMERIC NOT NULL DEFAULT 0,
  width NUMERIC NOT NULL DEFAULT 600,
  height NUMERIC NOT NULL DEFAULT 100,
  font_family TEXT DEFAULT 'HelveticaBold',
  font_size NUMERIC NOT NULL DEFAULT 36,
  font_weight TEXT DEFAULT 'bold',
  text_color TEXT DEFAULT '#1B2A4A',
  alignment TEXT DEFAULT 'center',  -- 'left' | 'center' | 'right'
  vertical_alignment TEXT DEFAULT 'middle',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Certificate Generation Jobs Table
CREATE TABLE IF NOT EXISTS public.certificate_generation_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  template_id UUID NOT NULL REFERENCES public.certificate_templates(id) ON DELETE CASCADE,
  total_count INT NOT NULL DEFAULT 0,
  completed_count INT NOT NULL DEFAULT 0,
  failed_count INT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'processing' | 'completed' | 'failed'
  error_log JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);

-- 4. Extend Certificates Table
ALTER TABLE public.certificates
  ADD COLUMN IF NOT EXISTS template_id UUID REFERENCES public.certificate_templates(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS certificate_number TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'completed', -- 'pending' | 'processing' | 'completed' | 'failed'
  ADD COLUMN IF NOT EXISTS generated_at TIMESTAMPTZ DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_cert_templates_event_id ON public.certificate_templates(event_id);
CREATE INDEX IF NOT EXISTS idx_cert_template_fields_template_id ON public.certificate_template_fields(template_id);
CREATE INDEX IF NOT EXISTS idx_cert_jobs_event_id ON public.certificate_generation_jobs(event_id);
