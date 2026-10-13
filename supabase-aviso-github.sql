-- Fut7 Scouting Pro: avisa a GitHub cuando cambian las estadísticas
-- para que se regenere datos.json. Ejecutar en Supabase > SQL Editor.

-- 1. Extensión para hacer llamadas HTTP desde la base de datos
create extension if not exists pg_net with schema extensions;

-- 2. Guardar el token de GitHub en el almacén cifrado (Vault).
--    Sustituye PEGA_AQUI_EL_TOKEN por tu token. Ejecuta esta línea solo una vez.
select vault.create_secret('PEGA_AQUI_EL_TOKEN', 'github_token_fut7');

-- 3. Función que avisa a GitHub solo si los datos han cambiado
create or replace function public.avisar_github_datos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  tok text;
begin
  if tg_op = 'UPDATE' and new.datos is not distinct from old.datos then
    return new;  -- no ha cambiado nada: no se avisa
  end if;

  select decrypted_secret into tok
  from vault.decrypted_secrets
  where name = 'github_token_fut7';

  perform net.http_post(
    url     := 'https://api.github.com/repos/cimorales/fut7-puntuaciones/dispatches',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || tok,
      'Accept', 'application/vnd.github+json',
      'User-Agent', 'fut7-supabase',
      'Content-Type', 'application/json'
    ),
    body    := jsonb_build_object('event_type', 'datos-actualizados')
  );
  return new;
end;
$$;

-- 4. Disparador sobre la tabla de jugadores
drop trigger if exists jugadores_avisar_github on public.jugadores;
create trigger jugadores_avisar_github
after insert or update on public.jugadores
for each row execute function public.avisar_github_datos();

-- Comprobación: tras cambiar una nota en la app, el último aviso debe tener status_code 204
-- select status_code, content, created from net._http_response order by created desc limit 5;
