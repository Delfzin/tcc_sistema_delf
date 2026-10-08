-- DELF, migração 0003: pessoas (4 tabelas)
--
--   core.usuario     perfil da pessoa (nome); toda conta tem um
--   core.instrutor   instrutor de uma academia
--   core.matricula   vínculo do aluno com uma academia
--   core.checkin     entrada e saída do aluno na academia

create table core.usuario (
  id bigint generated always as identity primary key,
  conta_id bigint not null,
  nome text not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  -- Apagar a conta apaga o perfil e, em cascata, tudo que é da pessoa.
  constraint usuario_conta foreign key (conta_id) references core.conta (id) on delete cascade,
  constraint usuario_conta_unica unique (conta_id),
  constraint usuario_nome_preenchido check (btrim(nome) <> '')
);

comment on table core.usuario is
  'Perfil da pessoa. Só guarda o nome; e-mail e senha ficam em core.conta. Não guardamos telefone, CPF nem data de nascimento.';

create trigger usuario_atualizado_em
  before update on core.usuario
  for each row execute function core.definir_atualizado_em();

create table core.instrutor (
  id bigint generated always as identity primary key,
  usuario_id bigint not null references core.usuario (id) on delete cascade,
  academia_id bigint not null references core.academia (id) on delete cascade,
  especialidade text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  constraint instrutor_unico unique (usuario_id, academia_id)
);

create table core.matricula (
  id bigint generated always as identity primary key,
  usuario_id bigint not null references core.usuario (id) on delete cascade,
  academia_id bigint not null references core.academia (id) on delete cascade,
  situacao text not null default 'ativa',
  iniciada_em timestamptz not null default now(),
  encerrada_em timestamptz,
  constraint matricula_situacao check (situacao in ('ativa', 'suspensa', 'encerrada')),
  constraint matricula_encerramento check ((situacao = 'encerrada') = (encerrada_em is not null)),
  constraint matricula_periodo check (encerrada_em is null or encerrada_em >= iniciada_em)
);

-- Só pode haver uma matrícula ativa por aluno em cada academia.
create unique index matricula_uma_ativa
  on core.matricula (usuario_id, academia_id)
  where situacao = 'ativa';

create index matricula_academia on core.matricula (academia_id, situacao);

create table core.checkin (
  id bigint generated always as identity primary key,
  usuario_id bigint not null references core.usuario (id) on delete cascade,
  academia_id bigint not null references core.academia (id) on delete cascade,
  entrada_em timestamptz not null default now(),
  saida_em timestamptz,
  constraint checkin_periodo check (saida_em is null or saida_em >= entrada_em)
);

-- Um aluno não pode ter dois check-ins abertos ao mesmo tempo.
create unique index checkin_um_aberto
  on core.checkin (usuario_id)
  where saida_em is null;

create index checkin_academia_data on core.checkin (academia_id, entrada_em);
create index checkin_usuario_data on core.checkin (usuario_id, entrada_em desc);

comment on table core.checkin is
  'Entrada e saída do aluno. É dado pessoal: mostra quando a pessoa esteve na academia.';

insert into core.migracao_aplicada (arquivo) values ('0003_pessoas.sql');
