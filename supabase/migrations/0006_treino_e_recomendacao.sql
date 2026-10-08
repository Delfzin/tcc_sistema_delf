-- DELF, migração 0006: treino e alternativas sugeridas (3 tabelas)
--
--   core.plano_treino   o treino de um aluno (por exemplo, "Treino A")
--   core.item_treino    cada exercício do treino, com séries e repetições
--   core.recomendacao   registro das alternativas sugeridas quando o aparelho estava ocupado
--
-- Fora do escopo: o sistema NÃO monta treino sozinho. O plano é escrito pelo
-- aluno ou pelo instrutor.

create table core.plano_treino (
  id bigint generated always as identity primary key,
  usuario_id bigint not null references core.usuario (id) on delete cascade,
  academia_id bigint not null references core.academia (id) on delete cascade,
  instrutor_id bigint references core.instrutor (id) on delete set null,
  nome text not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint plano_treino_nome_preenchido check (btrim(nome) <> '')
);

create index plano_treino_usuario on core.plano_treino (usuario_id) where ativo;

create trigger plano_treino_atualizado_em
  before update on core.plano_treino
  for each row execute function core.definir_atualizado_em();

create table core.item_treino (
  id bigint generated always as identity primary key,
  plano_treino_id bigint not null references core.plano_treino (id) on delete cascade,
  exercicio_id bigint not null references core.exercicio (id),
  ordem smallint not null,
  series smallint not null,
  repeticoes_min smallint,
  repeticoes_max smallint,
  observacao text,
  constraint item_treino_ordem_unica unique (plano_treino_id, ordem),
  constraint item_treino_ordem_positiva check (ordem >= 1),
  constraint item_treino_series_faixa check (series between 1 and 20),
  constraint item_treino_repeticoes_juntas check ((repeticoes_min is null) = (repeticoes_max is null)),
  constraint item_treino_repeticoes_faixa check (
    repeticoes_min is null or (repeticoes_min >= 1 and repeticoes_max >= repeticoes_min)
  )
);

create index item_treino_exercicio on core.item_treino (exercicio_id);

-- Registro de uma alternativa sugerida a um aluno quando o aparelho que ele
-- queria estava ocupado. A API ainda NÃO grava nesta tabela: ela existe para
-- fechar o modelo de 29 tabelas e será usada quando o site tiver o botão
-- "ir para esta alternativa".
create table core.recomendacao (
  id bigint generated always as identity primary key,
  academia_id bigint not null references core.academia (id) on delete cascade,
  usuario_id bigint references core.usuario (id) on delete set null,
  equipamento_origem_id bigint not null references core.equipamento (id),
  equipamento_sugerido_id bigint not null references core.equipamento (id),
  similaridade smallint not null,
  criado_em timestamptz not null default now(),
  constraint recomendacao_diferentes check (equipamento_origem_id <> equipamento_sugerido_id),
  constraint recomendacao_similaridade_faixa check (similaridade between 0 and 100)
);

create index recomendacao_academia_data on core.recomendacao (academia_id, criado_em);
create index recomendacao_usuario on core.recomendacao (usuario_id) where usuario_id is not null;

comment on table core.recomendacao is
  'Alternativa sugerida quando o aparelho estava ocupado. Reservada: a API ainda não grava aqui. Não é recomendação de treino, que está fora do escopo.';

insert into core.migracao_aplicada (arquivo) values ('0006_treino_e_recomendacao.sql');
