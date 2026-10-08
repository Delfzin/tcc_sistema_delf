-- DELF, migração 0007: avisos, integrações e métricas diárias (3 tabelas)
--
--   core.notificacao                     avisos para uma conta (por exemplo, alerta de manutenção ao dono)
--   core.integracao_externa              ligação com sistemas de gestão de terceiros
--   telemetria.metrica_diaria_academia   um resumo por academia por dia, calculado de sessões reais

create table core.notificacao (
  id bigint generated always as identity primary key,
  conta_id bigint not null references core.conta (id) on delete cascade,
  academia_id bigint references core.academia (id) on delete cascade,
  tipo text not null,
  titulo text not null,
  mensagem text not null,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  lida_em timestamptz,
  constraint notificacao_tipo check (tipo in ('manutencao_sugerida', 'sua_vez', 'aviso_do_sistema')),
  constraint notificacao_titulo_preenchido check (btrim(titulo) <> ''),
  constraint notificacao_mensagem_preenchida check (btrim(mensagem) <> '')
);

create index notificacao_conta_data on core.notificacao (conta_id, criado_em desc);
create index notificacao_nao_lidas on core.notificacao (conta_id) where lida_em is null;

comment on table core.notificacao is
  'Avisos para uma conta. Textos em português claro, sem emoji, sem travessão e sem tom de propaganda.';

-- Ligação com sistemas de gestão de academia (por exemplo, para importar a lista de alunos).
-- Ainda sem uso: existe para fechar o modelo de 29 tabelas.
create table core.integracao_externa (
  id bigint generated always as identity primary key,
  academia_id bigint not null references core.academia (id) on delete cascade,
  provedor text not null,
  identificador_externo text,
  ativa boolean not null default false,
  configuracao jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint integracao_externa_provedor_preenchido check (btrim(provedor) <> ''),
  constraint integracao_externa_unica unique (academia_id, provedor)
);

comment on table core.integracao_externa is
  'Ainda sem uso. NUNCA guardar senha, chave ou token de terceiros na coluna "configuracao": segredos ficam em variável de ambiente.';

create trigger integracao_externa_atualizado_em
  before update on core.integracao_externa
  for each row execute function core.definir_atualizado_em();

-- Resumo diário por academia.
--
-- Regra de ouro: uma taxa de uso só existe quando há base real para calculá-la.
-- Sem horário de funcionamento cadastrado, ou sem tempo coberto por sensor, a taxa
-- fica VAZIA e "motivo_sem_taxa" explica por quê. Nunca zero de enfeite.
create table telemetria.metrica_diaria_academia (
  academia_id bigint not null references core.academia (id) on delete cascade,
  dia date not null,
  calculada_em timestamptz not null default now(),
  equipamentos_total integer not null,
  equipamentos_com_sinal integer not null,
  sessoes_total integer not null,
  segundos_ocupados bigint not null,
  segundos_observados bigint not null,
  taxa_uso_percentual numeric(5, 2),
  motivo_sem_taxa text,
  hora_pico smallint,
  por_hora jsonb not null default '[]'::jsonb,
  por_equipamento jsonb not null default '[]'::jsonb,
  primary key (academia_id, dia),
  constraint metrica_taxa_faixa check (taxa_uso_percentual is null or taxa_uso_percentual between 0 and 100),
  -- Ou existe a taxa, ou existe o motivo de ela não existir. Nunca os dois, nunca nenhum.
  constraint metrica_taxa_ou_motivo check ((taxa_uso_percentual is null) = (motivo_sem_taxa is not null)),
  constraint metrica_hora_pico_faixa check (hora_pico is null or hora_pico between 0 and 23),
  constraint metrica_contagens check (
    equipamentos_total >= 0 and equipamentos_com_sinal between 0 and equipamentos_total
    and sessoes_total >= 0 and segundos_ocupados >= 0 and segundos_observados >= 0
  )
);

comment on table telemetria.metrica_diaria_academia is
  'Resumo de um dia (calendário do fuso da academia), calculado a partir de sessões de uso reais. O dia de hoje não fica aqui: é calculado na hora pela API.';
comment on column telemetria.metrica_diaria_academia.segundos_observados is
  'Tempo, dentro do horário de funcionamento, em que os sensores estavam falando. É o denominador da taxa. Tempo sem sinal NÃO entra, para não contar silêncio como aparelho livre.';
comment on column telemetria.metrica_diaria_academia.por_hora is
  'Lista de 24 itens (hora 0 a 23) com os segundos de uso somados de todos os aparelhos naquela hora.';
comment on column telemetria.metrica_diaria_academia.por_equipamento is
  'Lista com um item por aparelho: identificador, segundos de uso, segundos observados e taxa (vazia quando não há base).';

insert into core.migracao_aplicada (arquivo) values ('0007_engajamento_e_painel.sql');
