begin;
alter table public.visits add column if not exists manually_assigned boolean not null default false;
-- Preserve a direct assignment when future automatic visits are recalculated.
do $$declare definition text;begin
 select pg_get_functiondef('private.rotate_visits(uuid,date)'::regprocedure) into definition;
 if position('v.manually_assigned' in definition)=0 then
  if position('v.import_batch is not null or v.report is not null' in definition)=0 then raise exception 'Unexpected rotation function';end if;
  definition:=replace(definition,'v.import_batch is not null or v.report is not null','v.manually_assigned or v.import_batch is not null or v.report is not null');
  execute definition;
 end if;
end $$;
create or replace function private.relay_visit(p_patient uuid,p_visit uuid,p_target uuid,p_mode text,p_expected uuid) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();v public.visits%rowtype;t public.caregiver_profiles%rowtype;begin
 if actor is null or not private.is_member(p_patient) then raise exception 'Accès au dossier refusé';end if;
 if p_mode is null or p_mode not in ('request','agreed') then raise exception 'Mode de relais invalide';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_patient::text,0));
 select * into v from public.visits where id=p_visit and patient_id=p_patient for update;
 if not found or v.cancelled or v.visit_date<(now() at time zone 'Europe/Brussels')::date then raise exception 'Cette visite ne peut pas être réattribuée';end if;
 if coalesce(v.caregiver_id,v.profile_id) is distinct from p_expected then raise exception 'Le planning a changé. Actualisez avant de réessayer.';end if;
 if v.caregiver_id is distinct from actor and (p_mode='request' or not private.is_member(p_patient,true)) then raise exception 'Relais réservé à l’aidant de visite ou à l’administrateur';end if;
 select * into t from public.caregiver_profiles where patient_id=p_patient and (id=p_target or user_id=p_target) for update;
 if not found or coalesce(t.user_id,t.id)=coalesce(v.caregiver_id,v.profile_id) then raise exception 'Choisissez un autre aidant du cercle';end if;
 if t.user_id is not null and exists(select 1 from public.unavailability where patient_id=p_patient and caregiver_id=t.user_id and visit_date=v.visit_date) then raise exception 'Cet aidant est indisponible à cette date';end if;
 if p_mode='request' then
  if t.user_id is null then raise exception 'Cet aidant doit avoir un compte pour confirmer dans le site';end if;
  if exists(select 1 from public.exchanges where visit_id=v.id and status='pending') then raise exception 'Une demande attend déjà une réponse pour cette visite';end if;
  perform private.family_command(p_patient,'exchange',jsonb_build_object('visitId',v.id,'targetId',t.user_id));
 else
  update public.exchanges set status='declined' where visit_id=v.id and status='pending';
  update public.visits set caregiver_id=t.user_id,profile_id=t.id,manually_assigned=true where id=v.id;
  insert into public.audit_log(patient_id,user_id,action,entity_id) values(p_patient,actor,'visit_relay_agreed',v.id);
 end if;
end $$;
revoke all on function private.relay_visit(uuid,uuid,uuid,text,uuid) from public;
grant execute on function private.relay_visit(uuid,uuid,uuid,text,uuid) to authenticated;
create or replace function public.relay_visit(p_patient uuid,p_visit uuid,p_target uuid,p_mode text,p_expected uuid) returns void language sql security invoker set search_path='' as $$select private.relay_visit(p_patient,p_visit,p_target,p_mode,p_expected)$$;
revoke all on function public.relay_visit(uuid,uuid,uuid,text,uuid) from public;
grant execute on function public.relay_visit(uuid,uuid,uuid,text,uuid) to authenticated;
-- Keep the linked profile consistent when a normal request is accepted.
create or replace function private.sync_visit_assignee() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if new.caregiver_id is not null and new.caregiver_id is distinct from old.caregiver_id then
  select id into new.profile_id from public.caregiver_profiles where patient_id=new.patient_id and user_id=new.caregiver_id;
 end if;
 return new;
end $$;
revoke all on function private.sync_visit_assignee() from public;
do $$begin if not exists(select 1 from pg_trigger where tgrelid='public.visits'::regclass and tgname='sync_visit_assignee') then
 create trigger sync_visit_assignee before update of caregiver_id on public.visits for each row execute function private.sync_visit_assignee();
end if;end $$;
notify pgrst,'reload schema';
commit;
