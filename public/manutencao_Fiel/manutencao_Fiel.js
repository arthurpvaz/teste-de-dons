import { supabase } from '../supabase-client.js';

let pastors=[];
async function init(){
 const {data:{session}}=await supabase.auth.getSession();
 if(!session)return window.location.href='../login/login.html';
 const {data:profile,error}=await supabase.from('profiles').select('is_master,full_name').eq('id',session.user.id).single();
 if(error||!profile){alert('Perfil não encontrado.');return window.location.href='../login/login.html';}
 if(!profile.is_master){alert('Apenas o Admin Master pode acessar a gestão de pastores.');return window.location.href='../inicio/inicio.html';}
 const {data,error:profilesError}=await supabase.from('profiles').select('id,full_name,email,is_master,home_church_id').order('full_name');
 if(profilesError) return alert(profilesError.message);
 const {data:churches,error:churchError}=await supabase.rpc('list_all_churches');
 if(churchError)return alert(churchError.message);
 const map=Object.fromEntries((churches||[]).map(c=>[c.id,c.name]));
 pastors=(data||[]).map(p=>({...p,church_name:map[p.home_church_id]||'-'}));
 render();
}
function render(){
 const filtro=(document.getElementById('pesquisar')?.value||'').toLowerCase();
 const tbody=document.getElementById('corpo-tabela');tbody.innerHTML='';
 pastors.filter(p=>`${p.full_name||''} ${p.email||''}`.toLowerCase().includes(filtro)).forEach(p=>{
  const tr=document.createElement('tr');tr.innerHTML=`<td>${esc(p.full_name||'-')}</td><td>${esc(p.email||'-')}</td><td>${esc(p.church_name)}</td><td>${p.is_master?'Sim':'Não'}</td>`;tbody.appendChild(tr);
 });
 if(!tbody.children.length)tbody.innerHTML='<tr><td colspan="4">Nenhum pastor encontrado.</td></tr>';
}
function esc(v){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));}
window.cadastro=()=>window.location.href='../administrador_Cadastro/cadastro_Administrador.html';
document.getElementById('pesquisar')?.addEventListener('input',render);
document.getElementById('sair')?.addEventListener('click',async()=>{if(confirm('Deseja realmente sair?')){await supabase.auth.signOut();window.location.href='../login/login.html';}});
init();
