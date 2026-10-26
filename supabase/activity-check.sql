-- Objectif : produire une requête API légère pour le projet Supabase Free.
-- Fonctionnement : lire l'horloge PostgreSQL et renvoyer un booléen, sans accéder aux tables ni modifier de données.
-- Sécurité : exécution avec les droits de l'appelant, schéma de recherche vide et résultat sans donnée familiale.
-- Accès : autoriser uniquement les rôles anon et authenticated à appeler cette fonction.
create or replace function public.activity_check()
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$
  select clock_timestamp() is not null;
$$;

revoke all on function public.activity_check() from public, anon, authenticated;
grant execute on function public.activity_check() to anon, authenticated;
notify pgrst, 'reload schema';
