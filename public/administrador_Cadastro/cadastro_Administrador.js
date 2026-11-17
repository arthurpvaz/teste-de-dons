import { supabase } from '../supabase-client.js';

const formCard = document.getElementById('form-card');
document.getElementById('novo')?.addEventListener('click', () => formCard.hidden = !formCard.hidden);
document.getElementById('sair')?.addEventListener('click', async () => { await supabase.auth.signOut(); window.location.href='../login/login.html'; });

async function init() {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData.session) return window.location.href='../login/login.html';

  const { data: profile } = await supabase.from('profiles').select('is_master').eq('id', sessionData.session.user.id).single();
  if (!profile?.is_master) {
    alert('Apenas o Admin Master pode cadastrar pastores.');
    return window.location.href='../inicio/inicio.html';
  }

  const { data: churches, error: churchError } = await supabase.rpc('list_all_churches');
  if (churchError) return alert(churchError.message);
  const churchSelect = document.getElementById('church');
  (churches || []).forEach(c => {
    const option = document.createElement('option'); option.value=c.id; option.textContent=`${c.name}${c.city ? ` — ${c.city}` : ''}`; churchSelect.appendChild(option);
  });
  await carregarDados();
}

async function carregarDados() {
  const { data, error } = await supabase.from('profiles').select('id, full_name, email, is_master, home_church_id').order('full_name');
  if (error) return alert(`Erro ao carregar pastores: ${error.message}`);
  const { data: churches } = await supabase.rpc('list_all_churches');
  const churchMap = Object.fromEntries((churches || []).map(c => [c.id, c.name]));
  const tbody = document.getElementById('corpo-tabela'); tbody.innerHTML='';
  (data || []).forEach(p => {
    const tr=document.createElement('tr');
    tr.innerHTML=`<td>${escapeHtml(p.full_name || '-')}</td><td>${escapeHtml(p.email || '-')}</td><td>${escapeHtml(churchMap[p.home_church_id] || '-')}</td><td>${p.is_master ? 'Sim' : 'Não'}</td>`;
    tbody.appendChild(tr);
  });
}

function escapeHtml(v){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));}

document.getElementById('pastor-form')?.addEventListener('submit', async e => {
  e.preventDefault();
  const email=document.getElementById('email').value.trim();
  const full_name=document.getElementById('full_name').value.trim();
  const password=document.getElementById('password').value;
  const home_church_id=document.getElementById('church').value || null;
  try {
    const { data, error } = await supabase.functions.invoke('create-pastor', { body:{ email, full_name, password, home_church_id, grants: home_church_id ? [{church_id:home_church_id,level:'edit'}] : [] } });
    if(error) throw error;
    if(data?.error) throw new Error(data.error);
    alert('Pastor cadastrado com sucesso.');
    e.target.reset(); formCard.hidden=true; await carregarDados();
  } catch(err) { console.error(err); alert(`Não foi possível cadastrar: ${err.message || 'erro desconhecido'}`); }
});

init();
