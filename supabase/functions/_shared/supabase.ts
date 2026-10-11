import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { requireEnv } from "./http.ts";

/** Client service_role : contourne la RLS, à n'utiliser que côté serveur. */
export function adminClient(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Client « au nom de » l'utilisatrice qui appelle (JWT de l'en-tête Authorization). */
export function userClient(authorization: string): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
}

export type { SupabaseClient };
