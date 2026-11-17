import { supabase } from '../supabase-client.js';
const btn=document.getElementById('salvar');
btn?.addEventListener('click',async e=>{
 e.preventDefault();
 const email=document.getElementById('nome')?.value.trim();
 const senha=document.getElementById('senha')?.value;
 const confirmar=document.getElementById('redigitar_Senha')?.value;
 if(!email||!senha||!confirmar)return alert('Preencha todos os campos!');
 if(senha!==confirmar)return alert('Senha e confirmação não conferem.');
 if(senha.length<6)return alert('Senha menor que 6 caracteres.');
 try{
  const {data:churches,error:cErr}=await supabase.rpc('list_all_churches');if(cErr)throw cErr;
  const home=churches?.[0]?.id||null;
  const {data,error}=await supabase.functions.invoke('create-pastor',{body:{email,full_name:email,home_church_id:home,password:senha,grants:home?[{church_id:home,level:'edit'}]:[]}});
  if(error)throw error;if(data?.error)throw new Error(data.error);
  alert('Pastor cadastrado com sucesso!');
 }catch(err){console.error(err);alert(`Erro ao cadastrar: ${err.message||'erro desconhecido'}`)}
});
