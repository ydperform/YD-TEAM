alter table chat add column if not exists ch text not null default 'squad', add column if not exists client_id uuid, add column if not exists kind text not null default 'text', add column if not exists url text not null default '';
alter table chat drop constraint if exists chat_body_check;
alter table chat alter column body set default '';
drop function if exists chat_list(text, text);
drop function if exists chat_send(text, text, text);

create or replace function chat_list(p_u text, p_p text, p_ch text)
returns table(id bigint, author text, is_coach boolean, body text, kind text, url text, created_at timestamptz)
language sql security definer set search_path = public, extensions as
$$ select m.id, m.author, m.is_coach, m.body, m.kind, m.url, m.created_at from chat m
   join clients c on c.coach = m.coach
   where c.usr = lower(p_u) and c.pwd = crypt(p_p, c.pwd) and m.ch = p_ch and (p_ch = 'squad' or m.client_id = c.id)
   order by m.id desc limit 100 $$;

create or replace function chat_send(p_u text, p_p text, p_ch text, p_body text, p_kind text, p_url text) returns void
language plpgsql security definer set search_path = public, extensions as
$$ declare c clients; begin
  select * into c from clients where usr = lower(p_u) and pwd = crypt(p_p, pwd);
  if not found then raise exception 'No permitido'; end if;
  if p_ch not in ('squad','priv') or p_kind not in ('text','audio','video','image') then raise exception 'Datos no válidos'; end if;
  if length(trim(coalesce(p_body,''))) = 0 and coalesce(p_url,'') = '' then return; end if;
  insert into chat(coach, author, body, ch, client_id, kind, url)
  values (c.coach, c.name, left(trim(coalesce(p_body,'')), 1000), p_ch, case when p_ch = 'priv' then c.id end, p_kind, coalesce(p_url,'')); end $$;

revoke execute on function chat_list(text, text, text), chat_send(text, text, text, text, text, text) from public;
grant execute on function chat_list(text, text, text), chat_send(text, text, text, text, text, text) to anon, authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('chat', 'chat', true, 26214400, array['audio/*','video/*','image/*'])
on conflict (id) do update set public = true, file_size_limit = 26214400;
drop policy if exists chat_up on storage.objects;
create policy chat_up on storage.objects for insert to anon, authenticated with check (bucket_id = 'chat');
