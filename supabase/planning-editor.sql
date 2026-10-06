begin;
create table if not exists public.visit_recurrences (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id),
 profile_id uuid not null references public.caregiver_profiles(id), first_date date not null, last_date date not null,
 weeks integer not null check(weeks between 1 and 12), note text not null default '' check(length(note)<=2000),
 active boolean not null default true, version integer not null default 1,
 check(last_date>=first_date and last_date-first_date<=366)
);
create index if not exists visit_recurrences_patient_idx on public.visit_recurrences(patient_id);
alter table public.visit_recurrences enable row level security;
revoke all on public.visit_recurrences from anon,authenticated;
grant select on public.visit_recurrences to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='visit_recurrences' and policyname='family_read') then
 create policy family_read on public.visit_recurrences for select to authenticated using(private.is_member(patient_id));
 end if;
end $$;
alter table public.visits add column if not exists recurrence_id uuid references public.visit_recurrences(id);
create index if not exists visits_recurrence_idx on public.visits(recurrence_id) where recurrence_id is not null;
-- Automatic rotation must leave explicitly configured series unchanged.
do $$ declare body text; begin
 body:=pg_get_functiondef('private.rotate_visits(uuid,date)'::regprocedure);
 if position('v.recurrence_id is not null' in body)=0 then
  if position('v.manually_assigned or' in body)=0 then raise exception 'Install visit-relay.sql first'; end if;
  execute replace(body,'v.manually_assigned or','v.recurrence_id is not null or v.manually_assigned or');
 end if;
end $$;
create or replace function private.edit_visit(p_patient uuid,p_visit uuid,p_date date,p_profile uuid,p_note text,p_cancelled boolean,p_expected jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v public.visits; target public.caregiver_profiles; result uuid; begin
 if auth.uid() is null or not private.is_member(p_patient,true) then raise exception 'Seul l’administrateur peut modifier le planning.'; end if;
 if p_date is null or p_date < (now() at time zone 'Europe/Brussels')::date or p_date > (now() at time zone 'Europe/Brussels')::date+730 then raise exception 'Choisissez une date à venir, dans les deux prochaines années.'; end if;
 if p_cancelled is null or length(coalesce(p_note,''))>2000 then raise exception 'Informations de visite invalides.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_patient::text,0));
 select * into target from public.caregiver_profiles where patient_id=p_patient and (id=p_profile or user_id=p_profile);
 if not found then raise exception 'Choisissez un aidant de ce dossier.'; end if;
 if not p_cancelled and exists(select 1 from public.unavailability where patient_id=p_patient and caregiver_id=target.user_id and visit_date=p_date) then raise exception 'Cet aidant est indisponible à cette date.'; end if;
 if p_visit is not null then
  select * into v from public.visits where id=p_visit and patient_id=p_patient for update;
  if not found or v.visit_date < (now() at time zone 'Europe/Brussels')::date then raise exception 'Cette visite est archivée ou introuvable.'; end if;
  if p_expected is distinct from jsonb_build_object('date',v.visit_date,'caregiverId',coalesce(v.caregiver_id,v.profile_id)::text,'note',coalesce(v.source_note,''),'cancelled',v.cancelled) then raise exception 'Le planning a changé. Fermez cette fenêtre et actualisez avant de réessayer.'; end if;
 end if;
 if exists(select 1 from public.visits where patient_id=p_patient and visit_date=p_date and (p_visit is null or id<>p_visit)) then raise exception 'Une visite existe déjà à cette date. Modifiez cette visite.'; end if;
 if p_visit is null then
  insert into public.visits(patient_id,visit_date,caregiver_id,profile_id,source_note,cancelled,manually_assigned)
  values(p_patient,p_date,target.user_id,target.id,coalesce(p_note,''),p_cancelled,true) returning id into result;
 else
  update public.visits set visit_date=p_date,caregiver_id=target.user_id,profile_id=target.id,source_note=coalesce(p_note,''),cancelled=p_cancelled,manually_assigned=true,source_week=case when visit_date=p_date then source_week else null end,inferred=case when visit_date=p_date then inferred else false end where id=p_visit;
  update public.exchanges set status='declined' where visit_id=p_visit and status='pending';
  result:=p_visit;
 end if;
 insert into public.audit_log(patient_id,user_id,action,entity_id) values(p_patient,auth.uid(),'visit_edited',result);
 return result;
end $$;
create or replace function public.edit_visit(p_patient uuid,p_visit uuid,p_date date,p_profile uuid,p_note text,p_cancelled boolean,p_expected jsonb)
returns uuid language sql security invoker set search_path='' as $$ select private.edit_visit(p_patient,p_visit,p_date,p_profile,p_note,p_cancelled,p_expected) $$;
create or replace function private.save_visit_recurrence(p_patient uuid,p_id uuid,p_profile uuid,p_first date,p_last date,p_weeks integer,p_note text,p_active boolean,p_version integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.visit_recurrences; target public.caregiver_profiles; d date; today date:=(now() at time zone 'Europe/Brussels')::date; applied integer:=0; skipped integer:=0; begin
 if auth.uid() is null or not private.is_member(p_patient,true) then raise exception 'Seul l’administrateur peut modifier les récurrences.'; end if;
 if p_first is null or p_last is null or p_weeks is null or p_active is null or p_weeks not between 1 and 12 or p_last<p_first or p_last-p_first>366 or p_last>today+730 or length(coalesce(p_note,''))>2000 then raise exception 'Vérifiez les dates et la fréquence (1 à 12 semaines, période maximale d’un an).'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_patient::text,0));
 select * into target from public.caregiver_profiles where patient_id=p_patient and (id=p_profile or user_id=p_profile);
 if not found then raise exception 'Choisissez un aidant de ce dossier.'; end if;
 if p_id is null then
  if p_first<today then raise exception 'La première visite doit être à venir.'; end if;
  insert into public.visit_recurrences(patient_id,profile_id,first_date,last_date,weeks,note,active) values(p_patient,target.id,p_first,p_last,p_weeks,coalesce(p_note,''),p_active) returning * into r;
 else
  select * into r from public.visit_recurrences where patient_id=p_patient and id=p_id for update;
  if not found or r.version is distinct from p_version then raise exception 'Cette récurrence a changé. Fermez la fenêtre et actualisez.'; end if;
  update public.visit_recurrences set profile_id=target.id,first_date=p_first,last_date=p_last,weeks=p_weeks,note=coalesce(p_note,''),active=p_active,version=version+1 where id=r.id returning * into r;
 end if;
 -- Only generated, future visits without exceptions may be changed. Retain every record.
 update public.visits v set cancelled=true where v.recurrence_id=r.id and v.visit_date>=today and not v.manually_assigned and v.report is null and v.import_batch is null and not exists(select 1 from public.exchanges e where e.visit_id=v.id and e.status in ('pending','accepted'));
 if p_active then
  d:=p_first;
  while d<=p_last loop
   if d>=today then
    if exists(select 1 from public.unavailability where patient_id=p_patient and caregiver_id=target.user_id and visit_date=d) then skipped:=skipped+1;
    elsif exists(select 1 from public.visits v where v.patient_id=p_patient and v.visit_date=d and (v.recurrence_id is distinct from r.id or v.manually_assigned or v.report is not null or v.import_batch is not null or exists(select 1 from public.exchanges e where e.visit_id=v.id and e.status in ('pending','accepted')))) then skipped:=skipped+1;
    else
     insert into public.visits(patient_id,visit_date,caregiver_id,profile_id,source_note,recurrence_id) values(p_patient,d,target.user_id,target.id,coalesce(p_note,''),r.id)
     on conflict(patient_id,visit_date) do update set caregiver_id=excluded.caregiver_id,profile_id=excluded.profile_id,source_note=excluded.source_note,cancelled=false;
     applied:=applied+1;
    end if;
   end if;
   d:=d+p_weeks*7;
  end loop;
 end if;
 insert into public.audit_log(patient_id,user_id,action,entity_id) values(p_patient,auth.uid(),'visit_recurrence_saved',r.id);
 return jsonb_build_object('id',r.id,'applied',applied,'skipped',skipped);
end $$;
create or replace function public.save_visit_recurrence(p_patient uuid,p_id uuid,p_profile uuid,p_first date,p_last date,p_weeks integer,p_note text,p_active boolean,p_version integer)
returns jsonb language sql security invoker set search_path='' as $$ select private.save_visit_recurrence(p_patient,p_id,p_profile,p_first,p_last,p_weeks,p_note,p_active,p_version) $$;
revoke all on function private.edit_visit(uuid,uuid,date,uuid,text,boolean,jsonb),public.edit_visit(uuid,uuid,date,uuid,text,boolean,jsonb),private.save_visit_recurrence(uuid,uuid,uuid,date,date,integer,text,boolean,integer),public.save_visit_recurrence(uuid,uuid,uuid,date,date,integer,text,boolean,integer) from public,anon;
grant execute on function private.edit_visit(uuid,uuid,date,uuid,text,boolean,jsonb),public.edit_visit(uuid,uuid,date,uuid,text,boolean,jsonb),private.save_visit_recurrence(uuid,uuid,uuid,date,date,integer,text,boolean,integer),public.save_visit_recurrence(uuid,uuid,uuid,date,date,integer,text,boolean,integer) to authenticated;
notify pgrst,'reload schema';
commit;
