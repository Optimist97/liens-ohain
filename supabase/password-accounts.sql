begin;
create table private.account_usernames(user_id uuid primary key references auth.users on delete cascade,username text not null unique check(username ~ '^[a-z0-9._-]{3,40}$'));
alter table private.account_usernames enable row level security;
revoke all on private.account_usernames from public,anon,authenticated;grant all on private.account_usernames to service_role;
create table private.password_login_limits(bucket text primary key,started_at timestamptz not null default now(),attempts integer not null default 1);
alter table private.password_login_limits enable row level security;
revoke all on private.password_login_limits from public,anon,authenticated;grant all on private.password_login_limits to service_role;
create function private.family_login_names(p_patient uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
if not private.is_member(p_patient,true) then raise exception 'Réservé à l’administrateur';end if;
return(select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'username',n.username)),'[]') from public.memberships m join private.account_usernames n on n.user_id=m.user_id where m.patient_id=p_patient);end $$;
revoke all on function private.family_login_names(uuid) from public;grant execute on function private.family_login_names(uuid) to authenticated;
create function public.family_login_names(p_patient uuid) returns jsonb language sql security invoker set search_path='' as $$select private.family_login_names(p_patient)$$;
revoke all on function public.family_login_names(uuid) from public;grant execute on function public.family_login_names(uuid) to authenticated;
create function private.password_login_lookup(p_username text,p_bucket text) returns jsonb language plpgsql security definer set search_path='' as $$declare v_count integer;begin
insert into private.password_login_limits(bucket) values(p_bucket) on conflict(bucket) do update set started_at=case when private.password_login_limits.started_at<now()-interval '5 minutes' then now() else private.password_login_limits.started_at end,attempts=case when private.password_login_limits.started_at<now()-interval '5 minutes' then 1 else private.password_login_limits.attempts+1 end returning attempts into v_count;
if v_count>10 then return jsonb_build_object('limited',true);end if;
return(select jsonb_build_object('email',u.email) from private.account_usernames n join auth.users u on u.id=n.user_id where n.username=p_username and exists(select 1 from public.memberships m where m.user_id=u.id));end $$;
revoke all on function private.password_login_lookup(text,text) from public,anon,authenticated;grant execute on function private.password_login_lookup(text,text) to service_role;
create or replace function public.password_login_lookup(p_username text,p_bucket text) returns jsonb language sql security invoker set search_path='' as $$select private.password_login_lookup(p_username,p_bucket)$$;
revoke all on function public.password_login_lookup(text,text) from public,anon,authenticated;grant execute on function public.password_login_lookup(text,text) to service_role;
create function private.password_account_target(p_actor uuid,p_patient uuid,p_target uuid,p_email text,p_username text) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.caregiver_profiles%rowtype;v_user uuid;begin
if not exists(select 1 from public.memberships where patient_id=p_patient and user_id=p_actor and role='admin') then raise exception 'Réservé à l’administrateur';end if;
if p_username !~ '^[a-z0-9._-]{3,40}$' or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Identifiant ou adresse invalide';end if;
select * into p from public.caregiver_profiles where patient_id=p_patient and (id=p_target or user_id=p_target);if not found then raise exception 'Aidant introuvable';end if;
if p.user_id is not null then
 if p.user_id<>p_actor and exists(select 1 from public.memberships where patient_id=p_patient and user_id=p.user_id and role='admin') then raise exception 'Chaque administrateur gère son propre mot de passe';end if;
 if not exists(select 1 from auth.users where id=p.user_id and lower(email)=lower(p_email)) then raise exception 'Adresse du compte incorrecte';end if;v_user:=p.user_id;
else
 select id into v_user from auth.users where lower(email)=lower(p_email) and raw_app_meta_data->>'provisioned_by'=p_actor::text and raw_app_meta_data->>'provisioned_patient'=p_patient::text and raw_app_meta_data->>'provisioned_profile'=p.id::text;
 if exists(select 1 from auth.users where lower(email)=lower(p_email) and id is distinct from v_user) then raise exception 'Cette adresse possède déjà un compte. Utilisez une invitation.';end if;
end if;
if exists(select 1 from private.account_usernames where username=p_username and user_id is distinct from v_user) then raise exception 'Cet identifiant est déjà utilisé';end if;
return jsonb_build_object('profileId',p.id,'userId',v_user);end $$;
revoke all on function private.password_account_target(uuid,uuid,uuid,text,text) from public,anon,authenticated;grant execute on function private.password_account_target(uuid,uuid,uuid,text,text) to service_role;
create or replace function public.password_account_target(p_actor uuid,p_patient uuid,p_target uuid,p_email text,p_username text) returns jsonb language sql security invoker set search_path='' as $$select private.password_account_target(p_actor,p_patient,p_target,p_email,p_username)$$;
revoke all on function public.password_account_target(uuid,uuid,uuid,text,text) from public,anon,authenticated;grant execute on function public.password_account_target(uuid,uuid,uuid,text,text) to service_role;
create function private.attach_password_account(p_actor uuid,p_patient uuid,p_profile uuid,p_user uuid,p_email text,p_username text) returns void language plpgsql security definer set search_path='' as $$declare p public.caregiver_profiles%rowtype;begin
perform pg_advisory_xact_lock(hashtextextended(p_patient::text,0));
perform private.password_account_target(p_actor,p_patient,p_profile,p_email,p_username);
select * into p from public.caregiver_profiles where id=p_profile and patient_id=p_patient for update;
if not exists(select 1 from auth.users where id=p_user and lower(email)=lower(p_email) and email_confirmed_at is not null) then raise exception 'Compte invalide';end if;
if p.user_id is null then
 if not exists(select 1 from auth.users where id=p_user and raw_app_meta_data->>'provisioned_by'=p_actor::text and raw_app_meta_data->>'provisioned_patient'=p_patient::text and raw_app_meta_data->>'provisioned_profile'=p.id::text) then raise exception 'Compte non autorisé';end if;
 if exists(select 1 from public.memberships where user_id=p_user) then raise exception 'Compte déjà rattaché';end if;
 update public.caregiver_profiles set target_email=lower(p_email) where id=p.id;
 insert into public.memberships(patient_id,user_id,display_name,role,color,rotation_order) values(p_patient,p_user,p.name,'aidant',p.slot,p.slot);
 update public.invitations set accepted_at=now() where patient_id=p_patient and target_email=lower(p_email) and accepted_at is null;
elsif p.user_id<>p_user then raise exception 'Compte incorrect';end if;
insert into private.account_usernames(user_id,username) values(p_user,p_username) on conflict(user_id) do update set username=excluded.username;
insert into public.audit_log(patient_id,user_id,action,entity_id) values(p_patient,p_actor,'account_access_update',p_user);
end $$;
revoke all on function private.attach_password_account(uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;grant execute on function private.attach_password_account(uuid,uuid,uuid,uuid,text,text) to service_role;
create or replace function public.attach_password_account(p_actor uuid,p_patient uuid,p_profile uuid,p_user uuid,p_email text,p_username text) returns void language sql security invoker set search_path='' as $$select private.attach_password_account(p_actor,p_patient,p_profile,p_user,p_email,p_username)$$;
revoke all on function public.attach_password_account(uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;grant execute on function public.attach_password_account(uuid,uuid,uuid,uuid,text,text) to service_role;
commit;
