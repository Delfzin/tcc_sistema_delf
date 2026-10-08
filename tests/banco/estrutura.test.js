'use strict';

// Confere o formato do banco: as 29 tabelas, os tipos de data, a divisão por mês
// de leitura_sensor e o executor de migrações (inclusive do zero, num banco vazio).

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const { conectar, linhas, valor } = require('../suporte/banco');
const { criarCliente } = require('../../src/conexao');
const { aplicarPendentes, listarArquivos } = require('../../scripts/lib/migracoes');
const { apagarBanco, configurarTeste, recriarBanco } = require('../../scripts/lib/banco-de-teste');
const { urlComOutroBanco } = require('../../src/conexao');

const TABELAS_DO_MODELO = [
  // Identidade e acesso
  'core.conta', 'core.papel', 'core.permissao', 'core.papel_permissao',
  'core.conta_papel', 'core.sessao_login', 'core.log_auditoria',
  // Pessoas e academia
  'core.academia', 'core.usuario', 'core.instrutor', 'core.matricula', 'core.checkin',
  // Catálogo
  'core.grupo_muscular', 'core.tipo_equipamento', 'core.tipo_equipamento_equivalente',
  'core.exercicio', 'core.exercicio_grupo_muscular', 'core.exercicio_tipo_equipamento',
  // Equipamentos e sensores
  'core.equipamento', 'telemetria.sensor', 'telemetria.leitura_sensor',
  'telemetria.sessao_uso', 'core.manutencao_equipamento',
  // Treino
  'core.plano_treino', 'core.item_treino',
  // Recomendação
  'core.recomendacao',
  // Engajamento e painel
  'core.notificacao', 'core.integracao_externa', 'telemetria.metrica_diaria_academia',
];

describe('estrutura do banco', () => {
  let cliente;
  before(async () => {
    cliente = await conectar();
  });
  after(async () => {
    await cliente.end();
  });

  it('o modelo tem exatamente 29 tabelas, cada uma no schema certo', async () => {
    assert.equal(TABELAS_DO_MODELO.length, 29);
    const existentes = await linhas(
      cliente,
      `select n.nspname || '.' || c.relname as nome
         from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname in ('core', 'telemetria') and c.relkind in ('r', 'p')`
    );
    const nomes = new Set(existentes.map((l) => l.nome));
    for (const tabela of TABELAS_DO_MODELO) {
      assert.ok(nomes.has(tabela), `falta a tabela ${tabela}`);
    }
  });

  it('não existe tabela fora do modelo, além do controle de migrações e das partições', async () => {
    const extras = await linhas(
      cliente,
      `select n.nspname || '.' || c.relname as nome
         from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname in ('core', 'telemetria')
          and c.relkind in ('r', 'p')
          and not c.relispartition`
    );
    const esperadas = new Set([...TABELAS_DO_MODELO, 'core.migracao_aplicada']);
    const sobrando = extras.map((l) => l.nome).filter((nome) => !esperadas.has(nome));
    assert.deepEqual(sobrando, []);
  });

  it('nenhuma coluna usa data e hora sem fuso horário (tudo é timestamptz)', async () => {
    const colunas = await linhas(
      cliente,
      `select table_schema || '.' || table_name || '.' || column_name as coluna
         from information_schema.columns
        where table_schema in ('core', 'telemetria')
          and data_type = 'timestamp without time zone'`
    );
    assert.deepEqual(colunas, []);
  });

  it('leitura_sensor é dividida por mês e tem a partição do mês atual e dos dois seguintes', async () => {
    const tipo = await valor(
      cliente,
      `select c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'telemetria' and c.relname = 'leitura_sensor'`
    );
    assert.equal(tipo, 'p', 'leitura_sensor deveria ser tabela particionada');

    const estrategia = await valor(
      cliente,
      `select partstrat from pg_partitioned_table where partrelid = 'telemetria.leitura_sensor'::regclass`
    );
    assert.equal(estrategia, 'r', 'a divisão deveria ser por faixa (range)');

    const esperadas = await linhas(
      cliente,
      `select 'leitura_sensor_' || to_char(((now() at time zone 'America/Sao_Paulo') + make_interval(months => m)), 'YYYY_MM') as nome
         from generate_series(0, 2) as m`
    );
    const filhas = await linhas(
      cliente,
      `select c.relname from pg_inherits i
         join pg_class c on c.oid = i.inhrelid
        where i.inhparent = 'telemetria.leitura_sensor'::regclass`
    );
    const nomesFilhas = new Set(filhas.map((l) => l.relname));
    for (const { nome } of esperadas) {
      assert.ok(nomesFilhas.has(nome), `falta a partição ${nome}`);
    }
  });

  it('sessao_uso.usuario_id aceita vazio, porque o sensor não sabe quem usa', async () => {
    const aceita = await valor(
      cliente,
      `select is_nullable from information_schema.columns
        where table_schema = 'telemetria' and table_name = 'sessao_uso' and column_name = 'usuario_id'`
    );
    assert.equal(aceita, 'YES');
  });

  it('a conta guarda versão e data do aceite dos termos e da política de privacidade', async () => {
    const colunas = await linhas(
      cliente,
      `select column_name from information_schema.columns
        where table_schema = 'core' and table_name = 'conta'`
    );
    const nomes = colunas.map((l) => l.column_name);
    for (const esperada of [
      'termos_versao_aceita', 'termos_aceitos_em', 'privacidade_versao_aceita', 'privacidade_aceita_em',
    ]) {
      assert.ok(nomes.includes(esperada), `falta a coluna ${esperada}`);
    }
  });

  it('a conta recusa senha em texto puro e e-mail mal escrito', async () => {
    await assert.rejects(
      cliente.query(`insert into core.conta (email, senha_hash) values ('texto.puro@exemplo.com', 'delf1234')`),
      (erro) => erro.code === '23514'
    );
    await assert.rejects(
      cliente.query(`insert into core.conta (email, senha_hash) values ('SemMinuscula@Exemplo.com', 'scrypt$1$1$1$a$b')`),
      (erro) => erro.code === '23514'
    );
    await assert.rejects(
      cliente.query(`insert into core.conta (email, senha_hash) values ('sem-arroba', 'scrypt$1$1$1$a$b')`),
      (erro) => erro.code === '23514'
    );
  });

  it('a view de estado ao vivo existe', async () => {
    const existe = await valor(cliente, `select to_regclass('core.vw_estado_equipamento') is not null`);
    assert.equal(existe, true);
  });

  it('todas as migrações da pasta estão registradas como aplicadas', async () => {
    const arquivos = await listarArquivos();
    const registradas = (await linhas(cliente, 'select arquivo from core.migracao_aplicada order by arquivo')).map(
      (l) => l.arquivo
    );
    assert.deepEqual(registradas, arquivos);
  });

  it('rodar o executor de novo não aplica nada', async () => {
    const feitas = await aplicarPendentes(cliente);
    assert.deepEqual(feitas, []);
  });
});

describe('executor de migrações', () => {
  const { urlAdmin } = configurarTeste();
  const nomeZero = 'delf_teste_zero';
  const nomeSujo = 'delf_teste_sujo';
  const nomeFalha = 'delf_teste_falha';

  after(async () => {
    await apagarBanco(urlAdmin, nomeZero);
    await apagarBanco(urlAdmin, nomeSujo);
    await apagarBanco(urlAdmin, nomeFalha);
  });

  it('monta o banco inteiro do zero, num banco vazio', async () => {
    await recriarBanco(urlAdmin, nomeZero);
    const novo = criarCliente(urlComOutroBanco(urlAdmin, nomeZero));
    await novo.connect();
    try {
      const vazio = await valor(
        novo,
        `select count(*)::int from information_schema.tables where table_schema in ('core', 'telemetria')`
      );
      assert.equal(vazio, 0, 'o banco deveria começar vazio');

      const feitas = await aplicarPendentes(novo);
      assert.deepEqual(feitas, await listarArquivos());

      const total = await valor(
        novo,
        `select count(*)::int
           from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname in ('core', 'telemetria') and c.relkind in ('r', 'p') and not c.relispartition`
      );
      assert.equal(total, 29 + 1, '29 tabelas do modelo mais a tabela de controle');
    } finally {
      await novo.end();
    }
  });

  it('recusa banco que já tem tabelas mas não tem o controle de migrações', async () => {
    await recriarBanco(urlAdmin, nomeSujo);
    const sujo = criarCliente(urlComOutroBanco(urlAdmin, nomeSujo));
    await sujo.connect();
    try {
      await sujo.query('create schema core; create table core.conta (id int)');
      await assert.rejects(aplicarPendentes(sujo), /já tem tabelas/);
    } finally {
      await sujo.end();
    }
  });

  it('desfaz por inteiro a migração que falha e informa o arquivo', async () => {
    await recriarBanco(urlAdmin, nomeFalha);
    const pasta = await fs.mkdtemp(path.join(os.tmpdir(), 'delf-migracoes-'));
    await fs.writeFile(
      path.join(pasta, '0001_ok.sql'),
      `create schema core;
       create table core.migracao_aplicada (arquivo text primary key, aplicada_em timestamptz not null default now());
       insert into core.migracao_aplicada (arquivo) values ('0001_ok.sql');`
    );
    await fs.writeFile(
      path.join(pasta, '0002_quebrada.sql'),
      `create table core.deve_sumir (id int);
       select isto_nao_existe();`
    );
    const cliente = criarCliente(urlComOutroBanco(urlAdmin, nomeFalha));
    await cliente.connect();
    try {
      await assert.rejects(aplicarPendentes(cliente, { pasta }), /0002_quebrada\.sql falhou/);
      const sobrou = await valor(cliente, `select to_regclass('core.deve_sumir') is not null`);
      assert.equal(sobrou, false, 'a tabela criada pela migração quebrada deveria ter sido desfeita');
      const registradas = await linhas(cliente, 'select arquivo from core.migracao_aplicada');
      assert.deepEqual(registradas.map((l) => l.arquivo), ['0001_ok.sql']);
    } finally {
      await cliente.end();
      await fs.rm(pasta, { recursive: true, force: true });
    }
  });

  it('recusa dois arquivos com o mesmo número e nomes fora do padrão', async () => {
    const pasta = await fs.mkdtemp(path.join(os.tmpdir(), 'delf-migracoes-'));
    try {
      await fs.writeFile(path.join(pasta, '0001_a.sql'), 'select 1;');
      await fs.writeFile(path.join(pasta, '0001_b.sql'), 'select 1;');
      await assert.rejects(listarArquivos(pasta), /mesmo número|usam o número/);
      await fs.rm(path.join(pasta, '0001_b.sql'));
      await fs.writeFile(path.join(pasta, 'Nova Migracao.sql'), 'select 1;');
      await assert.rejects(listarArquivos(pasta), /não segue o padrão/);
    } finally {
      await fs.rm(pasta, { recursive: true, force: true });
    }
  });
});
