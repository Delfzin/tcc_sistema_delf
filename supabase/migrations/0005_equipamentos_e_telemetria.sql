-- DELF, migração 0005: aparelhos, sensores e telemetria (5 tabelas)
--
--   core.equipamento                 cada aparelho físico de uma academia
--   core.manutencao_equipamento      manutenções feitas ou em andamento
--   telemetria.sensor                o sensor (ESP32) preso a um aparelho
--   telemetria.sessao_uso            cada vez que alguém usou um aparelho
--   telemetria.leitura_sensor        mudanças de estado e voltas de silêncio, dividida por mês
--
-- Regra de isolamento entre academias: as tabelas filhas repetem academia_id e
-- ligam (equipamento_id, academia_id) a (id, academia_id) do aparelho. Assim o
-- próprio banco recusa, por exemplo, um sensor da academia A preso a um
-- aparelho da academia B.

-- ---------------------------------------------------------------------------
-- Aparelho
-- ---------------------------------------------------------------------------

create table core.equipamento (
  id bigint generated always as identity primary key,
  academia_id bigint not null references core.academia (id) on delete cascade,
  tipo_equipamento_id bigint not null references core.tipo_equipamento (id),
  nome text not null,
  localizacao text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint equipamento_nome_preenchido check (btrim(nome) <> ''),
  constraint equipamento_nome_unico unique (academia_id, nome),
  -- Necessário para as chaves compostas das tabelas filhas.
  constraint equipamento_id_academia unique (id, academia_id)
);

create index equipamento_academia_tipo on core.equipamento (academia_id, tipo_equipamento_id);

comment on table core.equipamento is
  'Aparelho físico. "ativo = false" tira o aparelho das telas sem apagar o histórico dele.';

create trigger equipamento_atualizado_em
  before update on core.equipamento
  for each row execute function core.definir_atualizado_em();

create table core.manutencao_equipamento (
  id bigint generated always as identity primary key,
  academia_id bigint not null,
  equipamento_id bigint not null,
  tipo text not null,
  descricao text not null,
  aberta_em timestamptz not null default now(),
  concluida_em timestamptz,
  registrada_por_conta_id bigint references core.conta (id) on delete set null,
  constraint manutencao_academia foreign key (academia_id)
    references core.academia (id) on delete cascade,
  constraint manutencao_equipamento foreign key (equipamento_id, academia_id)
    references core.equipamento (id, academia_id),
  constraint manutencao_tipo check (tipo in ('preventiva', 'corretiva')),
  constraint manutencao_descricao_preenchida check (btrim(descricao) <> ''),
  constraint manutencao_periodo check (concluida_em is null or concluida_em >= aberta_em)
);

-- Serve para saber depressa quais aparelhos estão em manutenção agora.
create index manutencao_em_aberto on core.manutencao_equipamento (equipamento_id)
  where concluida_em is null;
create index manutencao_equipamento_data on core.manutencao_equipamento (equipamento_id, aberta_em desc);

-- ---------------------------------------------------------------------------
-- Sensor
-- ---------------------------------------------------------------------------

create table telemetria.sensor (
  id bigint generated always as identity primary key,
  academia_id bigint not null,
  equipamento_id bigint not null,
  tipo text not null,
  chave_hash bytea not null,
  descricao text,
  ativo boolean not null default true,
  primeiro_sinal_em timestamptz,
  ultimo_sinal_em timestamptz,
  ultimo_estado text,
  ultima_mudanca_em timestamptz,
  desativado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint sensor_academia foreign key (academia_id)
    references core.academia (id) on delete cascade,
  constraint sensor_equipamento foreign key (equipamento_id, academia_id)
    references core.equipamento (id, academia_id),
  constraint sensor_chave_unica unique (chave_hash),
  constraint sensor_chave_tamanho check (octet_length(chave_hash) = 32),
  constraint sensor_tipo check (tipo in ('acelerometro', 'corrente')),
  constraint sensor_ultimo_estado check (ultimo_estado is null or ultimo_estado in ('livre', 'ocupado')),
  constraint sensor_desativacao check (ativo = (desativado_em is null))
) with (fillfactor = 70);

-- Só um sensor ativo por aparelho. Sensores antigos ficam desativados, com histórico.
create unique index sensor_um_ativo_por_equipamento
  on telemetria.sensor (equipamento_id)
  where ativo;

comment on table telemetria.sensor is
  'Sensor preso a um aparelho. Guarda só o resumo SHA-256 da chave dele. O sinal de vida (a cada poucos segundos ou minutos) só atualiza esta linha; não cria linha em leitura_sensor. fillfactor 70 deixa espaço para essas atualizações frequentes.';
comment on column telemetria.sensor.ultimo_sinal_em is
  'Última vez que o sensor falou, seja mudança de estado ou sinal de vida. Se ficar mais velha que minutos_sem_sinal da academia, o aparelho aparece como "sem sinal".';
comment on column telemetria.sensor.ultimo_estado is
  'Último estado que o sensor informou: livre ou ocupado. Vazio = ainda não informou, ou a rotina de manutenção fechou a sessão por falta de sinal.';
comment on column telemetria.sensor.primeiro_sinal_em is
  'Primeira vez que o sensor falou. Antes disso não há como saber o estado do aparelho, então esse tempo não entra nas métricas.';

create trigger sensor_atualizado_em
  before update on telemetria.sensor
  for each row execute function core.definir_atualizado_em();

-- ---------------------------------------------------------------------------
-- Sessão de uso
-- ---------------------------------------------------------------------------
-- Nasce da mudança de estado informada pelo sensor:
--   livre -> ocupado  abre a sessão
--   ocupado -> livre  fecha a sessão e a duração é calculada sozinha
-- O sensor não sabe quem está usando, por isso usuario_id pode ficar vazio.

create table telemetria.sessao_uso (
  id bigint generated always as identity primary key,
  academia_id bigint not null,
  equipamento_id bigint not null,
  sensor_id bigint references telemetria.sensor (id),
  usuario_id bigint references core.usuario (id) on delete set null,
  inicio_em timestamptz not null,
  fim_em timestamptz,
  encerrada_por text,
  duracao_segundos integer generated always as (
    case
      when fim_em is null then null
      else extract(epoch from (fim_em - inicio_em))::integer
    end
  ) stored,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint sessao_uso_academia foreign key (academia_id)
    references core.academia (id) on delete cascade,
  constraint sessao_uso_equipamento foreign key (equipamento_id, academia_id)
    references core.equipamento (id, academia_id),
  constraint sessao_uso_periodo check (fim_em is null or fim_em >= inicio_em),
  constraint sessao_uso_motivo_do_fim check (
    (fim_em is null) = (encerrada_por is null)
  ),
  constraint sessao_uso_motivo_valido check (
    encerrada_por is null or encerrada_por in ('sensor', 'sem_sinal', 'limite_de_tempo')
  )
);

-- O banco garante: no máximo UMA sessão aberta por aparelho.
create unique index sessao_uso_uma_aberta_por_equipamento
  on telemetria.sessao_uso (equipamento_id)
  where fim_em is null;

create index sessao_uso_academia_inicio on telemetria.sessao_uso (academia_id, inicio_em);
create index sessao_uso_equipamento_inicio on telemetria.sessao_uso (equipamento_id, inicio_em desc);
create index sessao_uso_usuario on telemetria.sessao_uso (usuario_id) where usuario_id is not null;

comment on column telemetria.sessao_uso.usuario_id is
  'Quase sempre vazio: o sensor não sabe quem usa o aparelho. Ligar o uso a uma pessoa é decisão futura e exige consentimento.';
comment on column telemetria.sessao_uso.encerrada_por is
  'sensor = o sensor avisou "livre"; sem_sinal = o sensor parou de falar no meio do uso; limite_de_tempo = passou da duração máxima da academia.';
comment on column telemetria.sessao_uso.duracao_segundos is
  'Calculada pelo banco (fim - início). Vazia enquanto a sessão está aberta.';

create trigger sessao_uso_atualizado_em
  before update on telemetria.sessao_uso
  for each row execute function core.definir_atualizado_em();

-- ---------------------------------------------------------------------------
-- Leituras dos sensores, divididas por mês
-- ---------------------------------------------------------------------------
-- Só entram aqui as mudanças de estado e as voltas de um silêncio. O sinal de
-- vida comum não cria linha. Cada mês fica numa partição própria, o que mantém
-- as consultas rápidas e permite descartar meses antigos sem apagar linha a linha.
--
-- Os meses seguem o calendário de São Paulo, o mesmo usado para fechar o dia
-- nas métricas.

create table telemetria.leitura_sensor (
  id bigint generated always as identity,
  sensor_id bigint not null references telemetria.sensor (id),
  academia_id bigint not null references core.academia (id) on delete cascade,
  equipamento_id bigint not null,
  recebido_em timestamptz not null default now(),
  estado text not null,
  mudou_estado boolean not null,
  sem_sinal_desde timestamptz,
  -- Em tabela particionada a chave primária precisa incluir a coluna de partição.
  constraint leitura_sensor_pk primary key (id, recebido_em),
  constraint leitura_sensor_equipamento foreign key (equipamento_id, academia_id)
    references core.equipamento (id, academia_id),
  constraint leitura_sensor_estado check (estado in ('livre', 'ocupado')),
  -- Uma linha só existe por um destes motivos: o estado mudou, ou o sensor voltou de um silêncio.
  constraint leitura_sensor_motivo check (mudou_estado or sem_sinal_desde is not null),
  constraint leitura_sensor_silencio_coerente check (sem_sinal_desde is null or sem_sinal_desde < recebido_em)
) partition by range (recebido_em);

create index leitura_sensor_sensor_data on telemetria.leitura_sensor (sensor_id, recebido_em desc);
create index leitura_sensor_equipamento_data on telemetria.leitura_sensor (equipamento_id, recebido_em desc);

comment on table telemetria.leitura_sensor is
  'Mudanças de estado informadas pelos sensores e voltas de silêncio. Particionada por mês (calendário de São Paulo). Não identifica ninguém.';
comment on column telemetria.leitura_sensor.sem_sinal_desde is
  'Preenchida quando o sensor voltou a falar depois de ficar sem sinal: marca quando o silêncio começou. O período [sem_sinal_desde, recebido_em] não conta como tempo livre nas métricas.';

-- Cria a partição do mês que contém o instante informado, se ainda não existir.
-- SECURITY DEFINER: roda com os poderes de quem criou a função, para que a API
-- (que não tem poder de criar tabelas) consiga pedir a partição do mês.
create function telemetria.garantir_particao_leitura(p_instante timestamptz)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_inicio_local timestamp;
  v_inicio timestamptz;
  v_fim timestamptz;
  v_nome text;
begin
  -- Contas de calendário são feitas em "timestamp" (sem fuso) para não
  -- dependerem do fuso da conexão de quem chamou.
  v_inicio_local := date_trunc('month', p_instante at time zone 'America/Sao_Paulo');
  v_inicio := v_inicio_local at time zone 'America/Sao_Paulo';
  v_fim := (v_inicio_local + interval '1 month') at time zone 'America/Sao_Paulo';
  v_nome := 'leitura_sensor_' || to_char(v_inicio_local, 'YYYY_MM');

  if to_regclass(format('telemetria.%I', v_nome)) is null then
    -- Uma trava evita que duas conexões tentem criar o mesmo mês ao mesmo tempo.
    perform pg_advisory_xact_lock(hashtext('delf.particao_leitura'));
    if to_regclass(format('telemetria.%I', v_nome)) is null then
      execute format(
        'create table telemetria.%I partition of telemetria.leitura_sensor for values from (%L) to (%L)',
        v_nome, v_inicio, v_fim
      );
    end if;
  end if;

  return v_nome;
end;
$$;

-- Garante a partição do mês atual e dos próximos meses. Chamada pela migração
-- e pela rotina de manutenção.
create function telemetria.garantir_particoes_leitura(p_meses_a_frente integer default 2)
returns text[]
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_base timestamp := now() at time zone 'America/Sao_Paulo';
  v_i integer;
  v_nomes text[] := array[]::text[];
begin
  for v_i in 0 .. greatest(p_meses_a_frente, 0) loop
    v_nomes := v_nomes || telemetria.garantir_particao_leitura(
      (v_base + make_interval(months => v_i)) at time zone 'America/Sao_Paulo'
    );
  end loop;
  return v_nomes;
end;
$$;

-- Funções que criam tabelas não devem ficar abertas a qualquer papel.
-- Quem pode executá-las é decidido nas permissões (migração de segurança).
revoke all on function telemetria.garantir_particao_leitura(timestamptz) from public;
revoke all on function telemetria.garantir_particoes_leitura(integer) from public;

select telemetria.garantir_particoes_leitura(2);

insert into core.migracao_aplicada (arquivo) values ('0005_equipamentos_e_telemetria.sql');
