'use strict';

// Confere a qualidade dos dados de referência (catálogo) e dos dados de teste (seed).

const { describe, it, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');

const { conectar, estadoDe, linhas, reiniciarDados, uma, valor } = require('../suporte/banco');
const { aplicarSeed } = require('../../scripts/lib/semente');
const { conferirSenha } = require('../../src/seguranca/senha');

describe('catálogo de aparelhos e exercícios', () => {
  let c;
  before(async () => {
    c = await conectar();
  });
  after(async () => {
    await c.end();
  });

  it('a similaridade é simétrica: se A é parecido com B, B é parecido com A pelo mesmo valor', async () => {
    const assimetricas = await linhas(
      c,
      `select e.tipo_equipamento_id, e.equivalente_id
         from core.tipo_equipamento_equivalente e
         left join core.tipo_equipamento_equivalente volta
           on volta.tipo_equipamento_id = e.equivalente_id
          and volta.equivalente_id = e.tipo_equipamento_id
          and volta.similaridade = e.similaridade
        where volta.tipo_equipamento_id is null`
    );
    assert.deepEqual(assimetricas, []);
  });

  it('todo par de aparelhos parecidos divide ao menos um músculo principal', async () => {
    const sem = await linhas(
      c,
      `select a.codigo as de, b.codigo as para
         from core.tipo_equipamento_equivalente e
         join core.tipo_equipamento a on a.id = e.tipo_equipamento_id
         join core.tipo_equipamento b on b.id = e.equivalente_id
        where not exists (
          select 1
            from core.vw_tipo_equipamento_grupo_muscular ga
            join core.vw_tipo_equipamento_grupo_muscular gb on gb.grupo_muscular_id = ga.grupo_muscular_id
           where ga.tipo_equipamento_id = e.tipo_equipamento_id
             and gb.tipo_equipamento_id = e.equivalente_id
             and (ga.principal or gb.principal)
        )`
    );
    assert.deepEqual(sem, []);
  });

  it('todo tipo de aparelho tem ao menos um exercício, e todo exercício tem músculo principal e aparelho', async () => {
    const tiposSemExercicio = await linhas(
      c,
      `select t.codigo from core.tipo_equipamento t
        where not exists (select 1 from core.exercicio_tipo_equipamento x where x.tipo_equipamento_id = t.id)`
    );
    assert.deepEqual(tiposSemExercicio, []);

    const semPrincipal = await linhas(
      c,
      `select e.codigo from core.exercicio e
        where not exists (
          select 1 from core.exercicio_grupo_muscular g where g.exercicio_id = e.id and g.principal
        )`
    );
    assert.deepEqual(semPrincipal, []);

    const semAparelho = await linhas(
      c,
      `select e.codigo from core.exercicio e
        where not exists (select 1 from core.exercicio_tipo_equipamento x where x.exercicio_id = e.id)`
    );
    assert.deepEqual(semAparelho, []);
  });

  it('a lista de alternativas do supino reto vem ordenada por similaridade: inclinado (85) antes do crucifixo (70)', async () => {
    const alternativas = await linhas(
      c,
      `select b.codigo, e.similaridade
         from core.tipo_equipamento_equivalente e
         join core.tipo_equipamento a on a.id = e.tipo_equipamento_id
         join core.tipo_equipamento b on b.id = e.equivalente_id
        where a.codigo = 'supino_reto_maquina'
        order by e.similaridade desc, b.codigo`
    );
    assert.equal(alternativas[0].codigo, 'supino_inclinado_maquina');
    assert.equal(alternativas[0].similaridade, 85);
    assert.equal(alternativas[1].codigo, 'crucifixo_maquina');
    assert.equal(alternativas[1].similaridade, 70);
  });

  it('o catálogo não tem equivalência de um tipo com ele mesmo nem valor fora de 0 a 100', async () => {
    await assert.rejects(
      c.query(
        `insert into core.tipo_equipamento_equivalente (tipo_equipamento_id, equivalente_id, similaridade)
         select id, id, 100 from core.tipo_equipamento limit 1`
      ),
      (erro) => erro.code === '23514'
    );
    await assert.rejects(
      c.query(
        `insert into core.tipo_equipamento_equivalente (tipo_equipamento_id, equivalente_id, similaridade)
         select a.id, b.id, 101 from core.tipo_equipamento a, core.tipo_equipamento b
          where a.codigo = 'esteira' and b.codigo = 'smith'`
      ),
      (erro) => erro.code === '23514'
    );
  });

  it('os papéis têm as permissões esperadas', async () => {
    const mapa = await linhas(
      c,
      `select p.codigo as papel, array_agg(pm.codigo order by pm.codigo) as permissoes
         from core.papel p
         join core.papel_permissao pp on pp.papel_id = p.id
         join core.permissao pm on pm.id = pp.permissao_id
        group by p.codigo order by p.codigo`
    );
    assert.deepEqual(mapa, [
      { papel: 'aluno', permissoes: ['aparelhos.ver', 'treino.proprio'] },
      { papel: 'dono', permissoes: ['aparelhos.ver', 'painel.ver'] },
      { papel: 'instrutor', permissoes: ['aparelhos.ver'] },
    ]);
  });
});

describe('dados de teste (seed)', () => {
  let c;
  before(async () => {
    c = await conectar();
  });
  beforeEach(async () => {
    await reiniciarDados(c);
  });
  after(async () => {
    await c.end();
  });

  it('todas as academias do seed têm nome de teste', async () => {
    const nomes = await linhas(c, 'select nome from core.academia order by nome');
    assert.deepEqual(nomes.map((l) => l.nome), ['Academia Teste Centro', 'Academia Teste Norte']);
  });

  it('a conta carlos@exemplo.com existe e a senha delf1234 confere com o resumo guardado', async () => {
    const conta = await uma(c, `select senha_hash from core.conta where email = 'carlos@exemplo.com'`);
    assert.ok(conta);
    assert.equal(await conferirSenha('delf1234', conta.senha_hash), true);
    assert.equal(await conferirSenha('outra-senha', conta.senha_hash), false);
  });

  it('existe uma conta de dono para cada academia de teste, e ninguém guarda a senha em texto puro', async () => {
    const donos = await valor(
      c,
      `select count(*)::int from core.conta_papel cp join core.papel p on p.id = cp.papel_id where p.codigo = 'dono'`
    );
    assert.equal(donos, 2);
    const emTextoPuro = await valor(c, `select count(*)::int from core.conta where senha_hash not like 'scrypt$%'`);
    assert.equal(emTextoPuro, 0);
  });

  it('uma conta de teste ainda não aceitou os termos, para testar o aceite novo', async () => {
    const conta = await uma(
      c,
      `select termos_versao_aceita, termos_aceitos_em, privacidade_versao_aceita, privacidade_aceita_em
         from core.conta where email = 'sem.aceite@exemplo.com'`
    );
    assert.deepEqual(conta, {
      termos_versao_aceita: null,
      termos_aceitos_em: null,
      privacidade_versao_aceita: null,
      privacidade_aceita_em: null,
    });
  });

  it('os 18 aparelhos de teste começam sem sinal, porque nenhum sensor falou ainda', async () => {
    const estados = await linhas(c, 'select estado, count(*)::int as total from core.vw_estado_equipamento group by estado');
    assert.deepEqual(estados, [{ estado: 'sem_sinal', total: 18 }]);
  });

  it('cada aparelho tem um sensor ativo, e as chaves de teste têm o resumo de 32 bytes', async () => {
    const sensores = await linhas(
      c,
      `select s.tipo, octet_length(s.chave_hash) as bytes, t.categoria
         from telemetria.sensor s
         join core.equipamento e on e.id = s.equipamento_id
         join core.tipo_equipamento t on t.id = e.tipo_equipamento_id
        where s.ativo`
    );
    assert.equal(sensores.length, 18);
    assert.ok(sensores.every((s) => s.bytes === 32));
    assert.ok(
      sensores.every((s) => (s.categoria === 'cardio' ? s.tipo === 'corrente' : s.tipo === 'acelerometro')),
      'cardio usa sensor de corrente; musculação usa acelerômetro'
    );
  });

  it('as chaves de teste documentadas no seed correspondem aos sensores', async () => {
    for (let n = 1; n <= 14; n += 1) {
      const chave = `chave-de-teste-centro-${String(n).padStart(2, '0')}`;
      const achou = await valor(
        c,
        `select count(*)::int from telemetria.sensor where chave_hash = sha256(convert_to($1, 'UTF8'))`,
        [chave]
      );
      assert.equal(achou, 1, `falta o sensor da chave ${chave}`);
    }
    for (let n = 1; n <= 4; n += 1) {
      const chave = `chave-de-teste-norte-${String(n).padStart(2, '0')}`;
      const achou = await valor(
        c,
        `select count(*)::int from telemetria.sensor where chave_hash = sha256(convert_to($1, 'UTF8'))`,
        [chave]
      );
      assert.equal(achou, 1, `falta o sensor da chave ${chave}`);
    }
  });

  it('o treino do Carlos usa exercícios que existem como aparelho na Academia Teste Centro', async () => {
    const itens = await linhas(
      c,
      `select ex.codigo, count(e.id)::int as aparelhos
         from core.plano_treino pt
         join core.usuario u on u.id = pt.usuario_id
         join core.conta co on co.id = u.conta_id and co.email = 'carlos@exemplo.com'
         join core.item_treino it on it.plano_treino_id = pt.id
         join core.exercicio ex on ex.id = it.exercicio_id
         left join core.exercicio_tipo_equipamento et on et.exercicio_id = ex.id
         left join core.equipamento e on e.tipo_equipamento_id = et.tipo_equipamento_id and e.academia_id = pt.academia_id
        group by ex.codigo, it.ordem order by it.ordem`
    );
    assert.equal(itens.length, 4);
    assert.ok(itens.every((i) => i.aparelhos >= 1));
  });

  it('o seed recusa rodar em banco que tem academia real', async () => {
    await c.query(`insert into core.academia (nome) values ('Academia de Verdade')`);
    try {
      await assert.rejects(aplicarSeed(c), /não é de teste/);
    } finally {
      await c.query(`delete from core.academia where nome = 'Academia de Verdade'`);
    }
  });

  it('o seed recusa rodar duas vezes seguidas', async () => {
    await assert.rejects(aplicarSeed(c), /já foram carregados/);
  });

  it('apagar os dados de teste recusa banco com academia real', async () => {
    const { apagarDadosDeTeste } = require('../../scripts/lib/semente');
    await c.query(`insert into core.academia (nome) values ('Academia de Verdade')`);
    try {
      await assert.rejects(apagarDadosDeTeste(c), /não é de teste/);
      assert.equal(await valor(c, `select count(*)::int from core.academia where nome = 'Academia de Verdade'`), 1);
    } finally {
      await c.query(`delete from core.academia where nome = 'Academia de Verdade'`);
    }
  });

  it('o estado de um aparelho de teste muda quando o simulador (sensor) fala', async () => {
    const aparelho = await uma(
      c,
      `select e.id as equipamento_id, s.id as sensor_id
         from core.equipamento e join telemetria.sensor s on s.equipamento_id = e.id
        where e.nome = 'Esteira 1' and e.academia_id = (select id from core.academia where nome = 'Academia Teste Centro')`
    );
    assert.equal(await estadoDe(c, aparelho.equipamento_id), 'sem_sinal');
    await c.query('select * from telemetria.registrar_leitura($1, $2)', [aparelho.sensor_id, 'livre']);
    assert.equal(await estadoDe(c, aparelho.equipamento_id), 'livre');
  });
});
