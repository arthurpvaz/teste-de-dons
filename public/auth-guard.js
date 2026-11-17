import { supabase } from './supabase-client.js';

export async function getSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session;
}

export async function requireSession(redirect = '/login/login.html') {
  const session = await getSession();
  if (!session) {
    window.location.href = redirect;
    return null;
  }
  return session;
}

export async function logout() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}
