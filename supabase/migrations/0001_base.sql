-- DELF, migração 0001: base do banco
--
-- O que faz:
--   1. Cria os dois schemas (as duas "pastas" do banco): "core" e "telemetria".
--   2. Cria a tabela que anota quais migrações já foram aplicadas.
--   3. Cria duas funções pequenas usadas por várias tabelas.
--
-- Como aplicar: cole o arquivo inteiro no editor SQL, ou rode "npm run migrar".
-- Aplique os arquivos sempre em ordem numérica, num banco vazio.

create schema if not exists core;
create schema if not exists telemetria;

comment on schema core is
  'Pessoas, academias, catálogo de aparelhos e exercícios, treinos e avisos.';
comment on schema telemetria is
  'Sensores, leituras dos sensores, sessões de uso dos aparelhos e métricas diárias.';

-- Controle das migrações. Não faz parte das 29 tabelas do modelo.
create table core.migracao_aplicada (
  arquivo text primary key,
  aplicada_em timestamptz not null default now()
);

comment on table core.migracao_aplicada is
  'Controle: quais arquivos de supabase/migrations já foram aplicados. Não faz parte das 29 tabelas do modelo.';

-- Mantém a coluna atualizado_em sempre correta, sem depender da API lembrar.
create function core.definir_atualizado_em() returns trigger
language plpgsql
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- Diz se um nome de fuso horário existe (por exemplo, America/Sao_Paulo).
-- Usada para o banco recusar um fuso escrito errado.
create function core.fuso_horario_valido(p_nome text) returns boolean
language sql
stable
as $$
  select exists (select 1 from pg_timezone_names where name = p_nome);
$$;

insert into core.migracao_aplicada (arquivo) values ('0001_base.sql');
