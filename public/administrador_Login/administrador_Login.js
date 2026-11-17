import { supabase } from '../supabase-client.js';
const form=document.getElementById('form-login');
form?.addEventListener('submit',async e=>{
 e.preventDefault();
 const email=document.getElementById('usuario')?.value.trim();
 const senha=document.getElementById('senha')?.value;
 if(!email||!senha)return alert('Informe o e-mail e a senha.');
 try{
  const {error}=await supabase.auth.signInWithPassword({email,password:senha});
  if(error)throw error;
  window.location.href='../manutencao_Fiel/manutencao_Fiel.html';
 }catch(err){console.error(err);alert(`Não foi possível entrar: ${err.message||'e-mail ou senha inválidos.'}`)}
});
