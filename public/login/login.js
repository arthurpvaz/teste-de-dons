import { supabase } from '../supabase-client.js';

const form = document.getElementById('form-login');
const voltar = document.getElementById('voltar');

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
      window.location.href = '../manutencao_Fiel/manutencao_Fiel.html';
    }
  } catch (err) {
    console.error(err);
    alert(`Não foi possível entrar: ${err.message || 'e-mail ou senha inválidos.'}`);
  }
});

voltar?.addEventListener('click', (e) => {
  e.preventDefault();
  if (window.parent && typeof window.parent.voltarParaDashboard === 'function') {
    window.parent.voltarParaDashboard();
  } else {
    window.location.href = '../inicio/inicio.html';
  }
});
