"use client";

import { createClient } from "@supabase/supabase-js";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()||"http://127.0.0.1:54321";
const supabasePublishableKey=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim()||"missing-supabase-anon-key";

export const crmSupabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export const crmSupabaseConfigured =
  Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim());
