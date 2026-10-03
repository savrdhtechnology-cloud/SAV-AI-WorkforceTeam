"use client";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();
export const crmSupabaseConfigured = Boolean(supabaseUrl && supabasePublishableKey);

// Resolve lazily so an unconfigured build can render a useful configuration error.
// No client or network request is created until both environment values exist.
let client: SupabaseClient | undefined;
function configuredClient(): SupabaseClient {
  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error("Supabase environment is not configured");
  }
  client ??= createClient(supabaseUrl, supabasePublishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  return client;
}
export const crmSupabase = new Proxy({} as SupabaseClient, {
  get(_target, property) {
    const instance = configuredClient();
    const value = Reflect.get(instance, property, instance);
    return typeof value === "function" ? value.bind(instance) : value;
  },
});
