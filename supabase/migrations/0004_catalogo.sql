-- DELF, migração 0004: catálogo (6 tabelas)
--
-- O catálogo é igual para todas as academias.
--
--   core.grupo_muscular                 músculos (peito, costas, quadríceps...)
--   core.tipo_equipamento               modelos de aparelho (leg press 45, esteira...)
--   core.tipo_equipamento_equivalente   quão parecido um tipo é de outro (0 a 100)
--   core.exercicio                      exercícios
--   core.exercicio_grupo_muscular       quais músculos cada exercício trabalha
--   core.exercicio_tipo_equipamento     em quais tipos de aparelho cada exercício é feito
--
-- O músculo de um aparelho NÃO é guardado direto nele: vem dos exercícios que
-- se fazem nele. Assim há uma única fonte da verdade.
-- Os dados ficam na migração 0009.

create table core.grupo_muscular (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nome text not null,
  constraint grupo_muscular_codigo_formato check (codigo ~ '^[a-z][a-z0-9_]*$')
);

create table core.tipo_equipamento (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nome text not null,
  categoria text not null,
  constraint tipo_equipamento_codigo_formato check (codigo ~ '^[a-z][a-z0-9_]*$'),
  -- musculacao usa sensor de movimento; cardio usa sensor de corrente do motor.
  constraint tipo_equipamento_categoria check (categoria in ('musculacao', 'cardio'))
);

create table core.tipo_equipamento_equivalente (
  tipo_equipamento_id bigint not null references core.tipo_equipamento (id) on delete cascade,
  equivalente_id bigint not null references core.tipo_equipamento (id) on delete cascade,
  similaridade smallint not null,
  primary key (tipo_equipamento_id, equivalente_id),
  constraint equivalente_diferente check (tipo_equipamento_id <> equivalente_id),
  constraint equivalente_faixa check (similaridade between 0 and 100)
);

comment on table core.tipo_equipamento_equivalente is
  'Grau de similaridade de 0 a 100 entre dois tipos de aparelho diferentes. Outra unidade do MESMO tipo vale 100 e não precisa estar aqui. Os valores são julgamento editorial, não medição.';

create table core.exercicio (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nome text not null unique,
  descricao text,
  constraint exercicio_codigo_formato check (codigo ~ '^[a-z][a-z0-9_]*$')
);

create table core.exercicio_grupo_muscular (
  exercicio_id bigint not null references core.exercicio (id) on delete cascade,
  grupo_muscular_id bigint not null references core.grupo_muscular (id) on delete cascade,
  principal boolean not null default true,
  primary key (exercicio_id, grupo_muscular_id)
);

create index exercicio_grupo_muscular_grupo on core.exercicio_grupo_muscular (grupo_muscular_id);

create table core.exercicio_tipo_equipamento (
  exercicio_id bigint not null references core.exercicio (id) on delete cascade,
  tipo_equipamento_id bigint not null references core.tipo_equipamento (id) on delete cascade,
  primary key (exercicio_id, tipo_equipamento_id)
);

create index exercicio_tipo_equipamento_tipo on core.exercicio_tipo_equipamento (tipo_equipamento_id);

insert into core.migracao_aplicada (arquivo) values ('0004_catalogo.sql');
