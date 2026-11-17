import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const config = window.SUPABASE_CONFIG;
if (!config?.url || !config?.publishableKey) {
  throw new Error('Supabase não configurado. Verifique public/supabase-config.js');
}

export const supabase = createClient(config.url, config.publishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});
