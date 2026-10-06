import {createClient} from 'npm:@supabase/supabase-js@2.99.1';
const origins=new Set(['https://optimist97.github.io','http://127.0.0.1:3000']);
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'';const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':origins.has(origin)?origin:'https://optimist97.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'Méthode refusée'},405);
 try{
  if(Number(req.headers.get('content-length')||0)>4096)return reply({error:'Requête trop volumineuse'},413);
  const body=await req.json();const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const password=typeof body.password==='string'?body.password:'';
  if(body.action==='login'){
   const username=String(body.username||'').trim().toLowerCase();if(!/^[a-z0-9._-]{3,40}$/.test(username)||!password||password.length>72)return reply({error:'Identifiants incorrects'},401);
   const hash=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(username));const bucket=Array.from(new Uint8Array(hash),x=>x.toString(16).padStart(2,'0')).join('');
   const {data:account,error}=await db.rpc('password_login_lookup',{p_username:username,p_bucket:bucket});if(error)return reply({error:'Connexion indisponible'},503);if(account?.limited)return reply({error:'Trop de tentatives. Réessayez dans cinq minutes.'},429);if(!account?.email)return reply({error:'Identifiants incorrects'},401);
   const login=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});const {data,error:authError}=await login.auth.signInWithPassword({email:account.email,password});if(authError||!data.session)return reply({error:'Identifiants incorrects'},401);
   return reply({access_token:data.session.access_token,refresh_token:data.session.refresh_token});
  }
  if(body.action!=='save')return reply({error:'Action inconnue'},400);
  const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');const {data:auth,error:authError}=await db.auth.getUser(token);if(authError||!auth.user)return reply({error:'Connectez-vous pour gérer les comptes'},401);
  const username=String(body.username||'').trim().toLowerCase(),email=String(body.email||'').trim().toLowerCase();if(!/^[a-z0-9._-]{3,40}$/.test(username)||password.length<10||new TextEncoder().encode(password).length>72)return reply({error:'Identifiant ou mot de passe invalide'},400);
  const args={p_actor:auth.user.id,p_patient:body.patientId,p_target:body.targetId,p_email:email,p_username:username};const {data:target,error:targetError}=await db.rpc('password_account_target',args);if(targetError)return reply({error:targetError.message},403);
  let userId=target.userId;
  if(userId){const {error}=await db.auth.admin.updateUserById(userId,{password});if(error)return reply({error:'Le mot de passe n’a pas pu être enregistré'},400)}
  else {const {data,error}=await db.auth.admin.createUser({email,password,email_confirm:true,app_metadata:{provisioned_by:auth.user.id,provisioned_patient:body.patientId,provisioned_profile:target.profileId}});if(error||!data.user)return reply({error:'Le compte n’a pas pu être créé. Vérifiez son adresse e-mail.'},400);userId=data.user.id}
  const {error}=await db.rpc('attach_password_account',{p_actor:auth.user.id,p_patient:body.patientId,p_profile:target.profileId,p_user:userId,p_email:email,p_username:username});if(error)return reply({error:'Le compte existe, mais son rattachement a échoué. Réessayez avec les mêmes informations.'},409);
  return reply({success:true});
 }catch{return reply({error:'Impossible de traiter cette demande'},400)}
});
