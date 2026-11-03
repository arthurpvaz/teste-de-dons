// supabase/functions/create-pastor/index.ts
//
// O Admin Master cadastra um pastor (usuário Auth + perfil + acessos) direto da plataforma.
// Usa a service_role (nunca exposta ao cliente). `verify_jwt = true` (config.toml) garante que
// só um usuário logado chega aqui; dentro, confirmamos que ele é master antes de criar.
//
// Chamada no frontend:
//   const { data, error } = await supabase.functions.invoke('create-pastor', {
//     body: { email, full_name, home_church_id, grants: [{ church_id, level }] }
//   })

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
    if (!jwt) return json({ error: "Não autenticado" }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    // Quem está chamando?
    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller.user) return json({ error: "Sessão inválida" }, 401);
    const callerId = caller.user.id;

    // É master?
    const { data: prof } = await admin
      .from("profiles").select("is_master").eq("id", callerId).single();
    if (!prof?.is_master) {
      return json({ error: "Apenas o Admin Master pode cadastrar pastores" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const { email, full_name, home_church_id, password, grants } = body ?? {};
    if (!email || !full_name) {
      return json({ error: "email e full_name são obrigatórios" }, 400);
    }

    // Cria o usuário já confirmado (o trigger handle_new_user cria o profiles).
    const tempPassword = password || crypto.randomUUID();
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { full_name },
    });
    if (createErr || !created.user) {
      return json({ error: createErr?.message ?? "Falha ao criar usuário" }, 400);
    }
    const newId = created.user.id;

    // Define nome e igreja-sede (home_church_id dá edit implícito nela).
    await admin.from("profiles")
      .update({ full_name, home_church_id: home_church_id ?? null })
      .eq("id", newId);

    // Grants de acesso cruzado opcionais: [{ church_id, level: 'read'|'edit' }].
    if (Array.isArray(grants) && grants.length) {
      const rows = grants
        .filter((g: any) => g?.church_id && (g.level === "read" || g.level === "edit"))
        .map((g: any) => ({
          user_id: newId, church_id: g.church_id, level: g.level, granted_by: callerId,
        }));
      if (rows.length) await admin.from("church_access").upsert(rows);
    }

    // temp_password só é devolvido quando geramos uma senha (para o master repassar).
    return json({ user_id: newId, email, temp_password: password ? undefined : tempPassword }, 200);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
