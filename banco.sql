-- Estrutura e regras do banco (Supabase / PostgreSQL), aplicadas no projeto sorteio-fitcasa.

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (auth.jwt() ->> 'email') = 'murilo@sindicompany.com.br'
    and exists (select 1 from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null),
    false)
$$;

create table public.lista (
  id smallint primary key default 1 check (id = 1),
  arquivo text not null,
  unidades jsonb not null,
  repetidas jsonb not null default '[]'::jsonb,
  publicada_em timestamptz not null default now()
);

create table public.resultados (
  sorteio smallint primary key check (sorteio between 0 and 3),
  vencedor text,
  suplentes jsonb not null default '[]'::jsonb,
  excluidos jsonb not null default '[]'::jsonb,
  aptos integer not null,
  animacao_ms integer not null default 0 check (animacao_ms between 0 and 15000),
  sorteado_em timestamptz not null default now()
);

create or replace function public.trava_lista() returns trigger
language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from public.resultados) then
    raise exception 'A lista não pode ser alterada depois que o sorteio começou.';
  end if;
  new.publicada_em := now();
  return new;
end $$;
create trigger trava_lista before insert or update on public.lista
  for each row execute function public.trava_lista();

create or replace function public.valida_resultado() returns trigger
language plpgsql set search_path = '' as $$
declare
  codigos text[] := array['N1','N3','A1','A3'];
  inscritos jsonb;
begin
  select unidades into inscritos from public.lista where id = 1;
  if inscritos is null then
    raise exception 'Carregue a lista de inscritos antes de sortear.';
  end if;
  if new.sorteio <> (select count(*) from public.resultados) then
    raise exception 'Os sorteios precisam seguir a ordem.';
  end if;
  if new.vencedor is not null and not exists (
      select 1 from jsonb_array_elements(inscritos) u
      where u->>'id' = new.vencedor and (u->'sorteios') ? codigos[new.sorteio + 1]) then
    raise exception 'O vencedor não está inscrito neste sorteio.';
  end if;
  new.sorteado_em := now();
  return new;
end $$;
create trigger valida_resultado before insert on public.resultados
  for each row execute function public.valida_resultado();

alter table public.lista enable row level security;
alter table public.resultados enable row level security;

create policy "todos leem a lista" on public.lista for select to anon, authenticated using (true);
create policy "admin publica a lista" on public.lista for insert to authenticated with check (public.is_admin());
create policy "admin troca a lista" on public.lista for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "todos leem resultados" on public.resultados for select to anon, authenticated using (true);
create policy "admin grava resultado" on public.resultados for insert to authenticated with check (public.is_admin());
-- sem política de update/delete: ninguém altera nem apaga um resultado gravado

revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
revoke execute on function public.trava_lista() from public, anon, authenticated;
revoke execute on function public.valida_resultado() from public, anon, authenticated;

alter publication supabase_realtime add table public.lista, public.resultados;
