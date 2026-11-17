import { supabase } from '../supabase-client.js';

let campuses=[];

async function init(){
 const {data,error}=await supabase.rpc('my_churches');
 if(error){showFeedback(`Não foi possível carregar os campi: ${error.message}`,'error');return;}
 campuses=data||[];
 const select=document.getElementById('form-campus');select.innerHTML='<option value="">Selecione o campus</option>';
 campuses.forEach(c=>{const o=document.createElement('option');o.value=c.slug;o.textContent=c.city?`${c.name} — ${c.city}`:c.name;select.appendChild(o);});
 const saved=localStorage.getItem('igrejaSelecionada');
 const selected=campuses.find(c=>c.name===saved)||campuses[0];
 if(selected)select.value=selected.slug;
 updateLink();
 select.addEventListener('change',updateLink);
}
function updateLink(){
 const slug=document.getElementById('form-campus')?.value;
 const base=new URL('../Formulario__DONS/formulario.html',window.location.href).href;
 document.getElementById('form-link').value=slug?`${base}?campus=${encodeURIComponent(slug)}`:base;
}
window.handleSendEmail=async e=>{
 e.preventDefault();
 const email=document.getElementById('destinatario-email').value.trim();
 if(!email)return showFeedback('Informe o e-mail do destinatário.','error');
 const subject=encodeURIComponent(document.getElementById('email-subject').value);
 const link=document.getElementById('form-link').value;
 const message=document.getElementById('email-message').value;
 const body=encodeURIComponent(`${message}\n\nLink de acesso:\n${link}`);
 window.location.href=`mailto:${email}?subject=${subject}&body=${body}`;
 showFeedback('Abrindo seu aplicativo de e-mail com o convite preenchido.','success');
};
window.openMailClient=()=>document.getElementById('send-form').dispatchEvent(new Event('submit',{cancelable:true}));
window.copyLinkForm=async()=>{try{await navigator.clipboard.writeText(document.getElementById('form-link').value);showFeedback('Link copiado com sucesso!','success')}catch(e){showFeedback('Não foi possível copiar o link.','error')}};
window.hideFeedbackAlert=()=>document.getElementById('feedback-alert').classList.add('hidden');
function showFeedback(msg,type){const box=document.getElementById('feedback-alert');document.getElementById('feedback-message').textContent=msg;box.className=`mb-6 p-4 rounded-xl text-sm flex items-center justify-between ${type==='success'?'bg-emerald-50 border border-emerald-200 text-emerald-800':'bg-red-50 border border-red-200 text-red-700'}`;box.classList.remove('hidden');}
init();
