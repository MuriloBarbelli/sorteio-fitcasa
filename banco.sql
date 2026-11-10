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

-- ---------------------------------------------------------------------------
-- Trava do sorteio válido e reinício com senha (histórico público)
-- ---------------------------------------------------------------------------
create table public.controle (
  id smallint primary key default 1 check (id = 1),
  travado boolean not null default false,
  travado_em timestamptz
);
insert into public.controle (id) values (1);
alter table public.controle enable row level security;
create policy "todos leem o controle" on public.controle for select to anon, authenticated using (true);

create table public.historico_resets (
  id bigint generated always as identity primary key,
  resetado_em timestamptz not null default now(),
  estava_travado boolean not null,
  resultados_apagados jsonb not null
);
alter table public.historico_resets enable row level security;
create policy "todos leem o histórico" on public.historico_resets for select to anon, authenticated using (true);

-- valida_resultado() passou a recusar gravação com o sorteio travado:
--   if (select travado from public.controle where id = 1) then raise exception 'O sorteio está travado.'; end if;

create or replace function public.travar_sorteio() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare quando timestamptz := now();
begin
  if not public.is_admin() then raise exception 'Sem permissão.'; end if;
  if (select count(*) from public.resultados) < 4 then raise exception 'Faça os 4 sorteios antes de travar.'; end if;
  if (select travado from public.controle where id = 1) then raise exception 'O sorteio já está travado.'; end if;
  update public.controle set travado = true, travado_em = quando where id = 1;
  return quando;
end $$;

-- Reiniciar exige login feito nos últimos 2 minutos (senha digitada de novo).
-- Os resultados apagados vão antes para o histórico público.
create or replace function public.resetar_sorteio() returns void
language plpgsql security definer set search_path = '' as $$
declare ultimo_login timestamptz;
begin
  if not public.is_admin() then raise exception 'Sem permissão.'; end if;
  select last_sign_in_at into ultimo_login from auth.users where id = auth.uid();
  if ultimo_login is null or ultimo_login < now() - interval '2 minutes' then
    raise exception 'Digite a senha novamente para reiniciar.';
  end if;
  if exists (select 1 from public.resultados) then
    insert into public.historico_resets (estava_travado, resultados_apagados)
    select (select travado from public.controle where id = 1),
           jsonb_agg(to_jsonb(r) order by r.sorteio) from public.resultados r;
  end if;
  -- "where sorteio >= 0" porque o Supabase recusa DELETE sem WHERE em chamadas pela API
  delete from public.resultados where sorteio >= 0;
  update public.controle set travado = false, travado_em = null where id = 1;
end $$;

revoke execute on function public.travar_sorteio() from public, anon;
revoke execute on function public.resetar_sorteio() from public, anon;
grant execute on function public.travar_sorteio() to authenticated;
grant execute on function public.resetar_sorteio() to authenticated;
alter publication supabase_realtime add table public.controle, public.historico_resets;
