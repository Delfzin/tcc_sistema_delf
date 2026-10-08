-- DELF, migração 0002: academia e controle de acesso (8 tabelas)
--
--   core.academia          cada academia cliente do sistema
--   core.conta             login (e-mail, senha guardada em forma de resumo) e aceite dos termos
--   core.papel             tipos de acesso: aluno, instrutor, dono
--   core.permissao         ações que um papel pode fazer
--   core.papel_permissao   quais permissões cada papel tem
--   core.conta_papel       qual papel uma conta tem, em qual academia
--   core.sessao_login      logins ativos (guarda só o resumo SHA-256 do token)
--   core.log_auditoria     registro de ações importantes

-- ---------------------------------------------------------------------------
-- Academia
-- ---------------------------------------------------------------------------
-- Os parâmetros de funcionamento dos sensores ficam aqui, por academia, para
-- poderem ser ajustados sem mexer em código nem regravar os sensores.

create table core.academia (
  id bigint generated always as identity primary key,
  nome text not null,
  cidade text,
  uf text,
  fuso_horario text not null default 'America/Sao_Paulo',
  abertura time,
  fechamento time,
  minutos_sem_sinal integer not null default 10,
  segundos_espera_para_livre integer not null default 120,
  intervalo_batimento_segundos integer not null default 60,
  duracao_maxima_sessao_minutos integer not null default 180,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint academia_nome_preenchido check (btrim(nome) <> ''),
  constraint academia_uf_formato check (uf is null or uf ~ '^[A-Z]{2}$'),
  constraint academia_fuso_valido check (core.fuso_horario_valido(fuso_horario)),
  constraint academia_horario_coerente check (
    (abertura is null) = (fechamento is null)
    and (abertura is null or abertura < fechamento)
  ),
  constraint academia_minutos_sem_sinal_faixa check (minutos_sem_sinal between 1 and 1440),
  constraint academia_espera_faixa check (segundos_espera_para_livre between 0 and 3600),
  constraint academia_batimento_faixa check (intervalo_batimento_segundos between 5 and 3600),
  constraint academia_batimento_cabe check (intervalo_batimento_segundos * 2 <= minutos_sem_sinal * 60),
  constraint academia_duracao_maxima_faixa check (duracao_maxima_sessao_minutos between 10 and 1440)
);

comment on table core.academia is 'Cada academia cliente. Toda consulta do sistema filtra por academia_id.';
comment on column core.academia.fuso_horario is
  'Fuso usado para fechar o dia nas métricas. Padrão America/Sao_Paulo.';
comment on column core.academia.abertura is
  'Hora de abertura, igual todos os dias. Sem ela e sem fechamento, a taxa de uso não pode ser calculada e a API devolve null com o motivo.';
comment on column core.academia.fechamento is
  'Hora de fechamento (pode ser 24:00 para academia 24 horas).';
comment on column core.academia.minutos_sem_sinal is
  'Sem leitura do sensor há mais que isto, o aparelho aparece como "sem sinal" e nunca como livre. Padrão 10, definido no manual de decisões.';
comment on column core.academia.segundos_espera_para_livre is
  'Descanso entre séries: depois que o sensor avisa "livre", o aparelho continua ocupado por este tempo e, se o sensor voltar a avisar "ocupado" dentro dele, é a mesma sessão. Valor inicial 120 s, SEM calibração com medição real; precisa ser ajustado em aparelho de verdade.';
comment on column core.academia.intervalo_batimento_segundos is
  'De quanto em quanto tempo o sensor deve mandar o sinal de vida. A API devolve este valor ao sensor. Precisa caber ao menos 2 vezes dentro de minutos_sem_sinal.';
comment on column core.academia.duracao_maxima_sessao_minutos is
  'Trava de segurança: uma sessão aberta por mais tempo que isto é fechada pela rotina de manutenção e marcada como limite_de_tempo.';

create trigger academia_atualizado_em
  before update on core.academia
  for each row execute function core.definir_atualizado_em();

-- ---------------------------------------------------------------------------
-- Conta (login)
-- ---------------------------------------------------------------------------

create table core.conta (
  id bigint generated always as identity primary key,
  email text not null,
  senha_hash text not null,
  ativa boolean not null default true,
  termos_versao_aceita text,
  termos_aceitos_em timestamptz,
  privacidade_versao_aceita text,
  privacidade_aceita_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint conta_email_unico unique (email),
  constraint conta_email_formato check (
    email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  -- Impede gravar uma senha em texto puro por engano: só aceita o formato do scrypt.
  constraint conta_senha_hash_formato check (senha_hash like 'scrypt$%'),
  -- Versão e data do aceite andam juntas: ou as duas existem, ou nenhuma.
  constraint conta_termos_completos check ((termos_versao_aceita is null) = (termos_aceitos_em is null)),
  constraint conta_privacidade_completa check ((privacidade_versao_aceita is null) = (privacidade_aceita_em is null))
);

comment on table core.conta is 'Dados de login. A senha nunca é guardada, só o resultado do scrypt.';
comment on column core.conta.termos_versao_aceita is 'Versão dos Termos de Uso que a pessoa aceitou. Vazio = nunca aceitou.';
comment on column core.conta.termos_aceitos_em is 'Data e hora em que aceitou os Termos de Uso.';
comment on column core.conta.privacidade_versao_aceita is 'Versão da Política de Privacidade que a pessoa aceitou.';
comment on column core.conta.privacidade_aceita_em is 'Data e hora em que aceitou a Política de Privacidade.';

create trigger conta_atualizado_em
  before update on core.conta
  for each row execute function core.definir_atualizado_em();

-- ---------------------------------------------------------------------------
-- Papéis e permissões
-- ---------------------------------------------------------------------------

create table core.papel (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nome text not null,
  descricao text
);

create table core.permissao (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  descricao text not null
);

create table core.papel_permissao (
  papel_id bigint not null references core.papel (id) on delete cascade,
  permissao_id bigint not null references core.permissao (id) on delete cascade,
  primary key (papel_id, permissao_id)
);

-- O papel vale para UMA academia. Assim o dono da academia A não é dono da B.
create table core.conta_papel (
  id bigint generated always as identity primary key,
  conta_id bigint not null references core.conta (id) on delete cascade,
  papel_id bigint not null references core.papel (id),
  academia_id bigint not null references core.academia (id) on delete cascade,
  criado_em timestamptz not null default now(),
  constraint conta_papel_unico unique (conta_id, papel_id, academia_id)
);

create index conta_papel_academia on core.conta_papel (academia_id);

comment on table core.conta_papel is
  'Papel de uma conta dentro de uma academia. O dono da academia A não tem poder na academia B.';

-- ---------------------------------------------------------------------------
-- Logins ativos
-- ---------------------------------------------------------------------------
-- O navegador guarda um código aleatório (o token). O banco guarda só o
-- resumo SHA-256 dele. Se o banco vazar, ninguém consegue entrar com o resumo.

create table core.sessao_login (
  id bigint generated always as identity primary key,
  conta_id bigint not null references core.conta (id) on delete cascade,
  token_hash bytea not null,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  revogado_em timestamptz,
  constraint sessao_login_token_unico unique (token_hash),
  constraint sessao_login_token_tamanho check (octet_length(token_hash) = 32),
  constraint sessao_login_validade check (expira_em > criado_em)
);

create index sessao_login_conta on core.sessao_login (conta_id);
create index sessao_login_expiracao on core.sessao_login (expira_em);

comment on table core.sessao_login is 'Logins ativos. Guarda só o resumo SHA-256 do token. Não guarda endereço IP nem dados do aparelho do usuário.';

-- ---------------------------------------------------------------------------
-- Registro de auditoria
-- ---------------------------------------------------------------------------

create table core.log_auditoria (
  id bigint generated always as identity primary key,
  conta_id bigint references core.conta (id) on delete set null,
  academia_id bigint references core.academia (id) on delete set null,
  acao text not null,
  entidade text,
  entidade_id bigint,
  detalhes jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint log_auditoria_acao_preenchida check (btrim(acao) <> '')
);

create index log_auditoria_academia_data on core.log_auditoria (academia_id, criado_em desc);
create index log_auditoria_conta on core.log_auditoria (conta_id) where conta_id is not null;

comment on table core.log_auditoria is
  'Ações importantes (aceite de termos, exclusão de conta, mudanças de configuração). Quando a conta é apagada, conta_id vira vazio e o registro continua sem ligação com a pessoa. Não colocar e-mail nem nome em "detalhes".';

insert into core.migracao_aplicada (arquivo) values ('0002_academia_e_acesso.sql');
