import { supabase } from './supabase-client.js';

const form = document.getElementById('form-login');
form?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const email = document.getElementById('nome')?.value.trim();
  const senha = document.getElementById('senha')?.value;
  if (!email || !senha) return alert('Informe o e-mail e a senha.');
  try {
    const { error } = await supabase.auth.signInWithPassword({ email, password: senha });
    if (error) throw error;
    if (window.parent && typeof window.parent.carregarManutencaoFiel === 'function') {
      window.parent.carregarManutencaoFiel();
    } else {
      window.location.href = './inicio/inicio.html';
    }
  } catch (err) {
    alert(`Não foi possível entrar: ${err.message || 'e-mail ou senha inválidos.'}`);
  }
});
