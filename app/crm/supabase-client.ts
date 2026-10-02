"use client";

import { createClient } from "@supabase/supabase-js";

const supabaseUrl = "https://ldffgetuzoeupuhoaubn.supabase.co";
const supabasePublishableKey = "sb_publishable_KzdI4K0qLXgi3MhA5GXPhg_6f5vB8By";

export const crmSupabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
