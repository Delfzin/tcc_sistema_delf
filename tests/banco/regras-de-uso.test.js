'use strict';

// Regras de uso dos aparelhos, testadas direto no banco:
//   * os três estados (livre, ocupado, sem sinal) e a regra "sem sinal nunca vira livre";
//   * sessão de uso: abre quando fica ocupado, fecha quando fica livre, com duração;
//   * descanso entre séries (espera antes de virar livre);
//   * sinal de vida não cria leitura nem sessão;
//   * isolamento entre academias;
//   * divisão de leitura_sensor por mês.
//
// Para "passar o tempo" sem esperar de verdade, os testes recuam as datas gravadas
// (por exemplo, o último sinal do sensor) com UPDATE.

const { describe, it, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');

const {
  aparelho,
  conectar,
  estadoDe,
  linhas,
  reiniciarDados,
  sensorInforma,
  uma,
  valor,
} = require('../suporte/banco');
const { criarCliente } = require('../../src/conexao');
const { configurarTeste } = require('../../scripts/lib/banco-de-teste');

const CENTRO = 'Academia Teste Centro';
const NORTE = 'Academia Teste Norte';

describe('regras de uso dos aparelhos', () => {
  let c;
  let supino; // Supino Reto 1, da Centro
  before(async () => {
    c = await conectar();
  });
  beforeEach(async () => {
    await reiniciarDados(c);
    supino = await aparelho(c, CENTRO, 'Supino Reto 1');
  });
  after(async () => {
    await c.end();
  });

  describe('estado ao vivo', () => {
    it('aparelho sem sensor aparece como sem sinal, nunca como livre', async () => {
      const tipo = await valor(c, `select id from core.tipo_equipamento where codigo = 'esteira'`);
      const novo = await uma(
        c,
        `insert into core.equipamento (academia_id, tipo_equipamento_id, nome)
         values ($1, $2, 'Esteira sem sensor') returning id`,
        [supino.academia_id, tipo]
      );
      assert.equal(await estadoDe(c, novo.id), 'sem_sinal');
    });

    it('sensor que ainda não falou aparece como sem sinal', async () => {
      assert.equal(await estadoDe(c, supino.equipamento_id), 'sem_sinal');
    });

    it('sensor que informou livre aparece como livre', async () => {
      await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(await estadoDe(c, supino.equipamento_id), 'livre');
    });

    it('sensor que informou ocupado aparece como ocupado', async () => {
      await sensorInforma(c, supino.sensor_id, 'ocupado');
      assert.equal(await estadoDe(c, supino.equipamento_id), 'ocupado');
    });

    it('sensor calado além do limite aparece como sem sinal, tanto se estava livre quanto se estava ocupado', async () => {
      for (const ultimoEstado of ['livre', 'ocupado']) {
        await sensorInforma(c, supino.sensor_id, ultimoEstado);
        await c.query(`update telemetria.sensor set ultimo_sinal_em = now() - interval '11 minutes' where id = $1`, [
          supino.sensor_id,
        ]);
        assert.equal(
          await estadoDe(c, supino.equipamento_id),
          'sem_sinal',
          `depois de ${ultimoEstado} e 11 minutos de silêncio deveria ser sem_sinal`
        );
        await reiniciarDados(c);
        supino = await aparelho(c, CENTRO, 'Supino Reto 1');
      }
    });

    it('sensor calado há menos que o limite ainda mostra o último estado', async () => {
      await sensorInforma(c, supino.sensor_id, 'ocupado');
      await c.query(`update telemetria.sensor set ultimo_sinal_em = now() - interval '9 minutes' where id = $1`, [
        supino.sensor_id,
      ]);
      assert.equal(await estadoDe(c, supino.equipamento_id), 'ocupado');
    });

    it('o limite de silêncio é da academia e pode ser mudado', async () => {
      await sensorInforma(c, supino.sensor_id, 'livre');
      await c.query(`update telemetria.sensor set ultimo_sinal_em = now() - interval '3 minutes' where id = $1`, [
        supino.sensor_id,
      ]);
      assert.equal(await estadoDe(c, supino.equipamento_id), 'livre', 'com limite de 10 minutos ainda é livre');

      await c.query(`update core.academia set minutos_sem_sinal = 2 where id = $1`, [supino.academia_id]);
      assert.equal(await estadoDe(c, supino.equipamento_id), 'sem_sinal', 'com limite de 2 minutos vira sem sinal');
    });

    it('aparelho em manutenção continua com um dos três estados e é sinalizado à parte', async () => {
      await sensorInforma(c, supino.sensor_id, 'livre');
      await c.query(
        `insert into core.manutencao_equipamento (academia_id, equipamento_id, tipo, descricao)
         values ($1, $2, 'corretiva', 'Cabo trocado')`,
        [supino.academia_id, supino.equipamento_id]
      );
      const linha = await uma(
        c,
        'select estado, em_manutencao from core.vw_estado_equipamento where equipamento_id = $1',
        [supino.equipamento_id]
      );
      assert.equal(linha.estado, 'livre');
      assert.equal(linha.em_manutencao, true);
    });

    it('o estado de uma academia não aparece na outra', async () => {
      const supinoNorte = await aparelho(c, NORTE, 'Supino Reto 1');
      await sensorInforma(c, supino.sensor_id, 'ocupado');
      assert.equal(await estadoDe(c, supino.equipamento_id), 'ocupado');
      assert.equal(await estadoDe(c, supinoNorte.equipamento_id), 'sem_sinal');

      const daNorte = await linhas(
        c,
        'select equipamento_id from core.vw_estado_equipamento where academia_id = $1',
        [supinoNorte.academia_id]
      );
      assert.equal(daNorte.length, 4);
      assert.ok(daNorte.every((l) => l.equipamento_id !== supino.equipamento_id));
    });
  });

  describe('sessão de uso', () => {
    it('livre para ocupado abre a sessão; ocupado para livre fecha com a duração calculada', async () => {
      await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(await valor(c, 'select count(*)::int from telemetria.sessao_uso'), 0);

      const aberta = await sensorInforma(c, supino.sensor_id, 'ocupado');
      assert.equal(aberta.houve_mudanca, true);
      const sessao = await uma(c, 'select * from telemetria.sessao_uso where id = $1', [aberta.sessao_id]);
      assert.equal(sessao.fim_em, null);
      assert.equal(sessao.duracao_segundos, null);
      assert.equal(sessao.usuario_id, null, 'o sensor não sabe quem usa');
      assert.equal(sessao.academia_id, supino.academia_id);
      assert.equal(sessao.equipamento_id, supino.equipamento_id);

      await c.query(`update telemetria.sessao_uso set inicio_em = now() - interval '90 seconds' where id = $1`, [
        sessao.id,
      ]);
      const fechada = await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(fechada.sessao_id, sessao.id);

      const depois = await uma(c, 'select * from telemetria.sessao_uso where id = $1', [sessao.id]);
      assert.ok(depois.fim_em instanceof Date);
      assert.equal(depois.encerrada_por, 'sensor');
      assert.ok(
        depois.duracao_segundos >= 90 && depois.duracao_segundos <= 95,
        `duração esperada perto de 90 s, veio ${depois.duracao_segundos}`
      );
    });

    it('sinal de vida repetido não cria leitura nem sessão nova', async () => {
      for (let i = 0; i < 3; i += 1) await sensorInforma(c, supino.sensor_id, 'ocupado');
      assert.equal(await valor(c, 'select count(*)::int from telemetria.leitura_sensor'), 1);
      assert.equal(await valor(c, 'select count(*)::int from telemetria.sessao_uso'), 1);

      for (let i = 0; i < 3; i += 1) await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(await valor(c, 'select count(*)::int from telemetria.leitura_sensor'), 2);
      assert.equal(await valor(c, 'select count(*)::int from telemetria.sessao_uso'), 1);
    });

    it('o sinal de vida atualiza o último sinal do sensor', async () => {
      await sensorInforma(c, supino.sensor_id, 'livre');
      await c.query(`update telemetria.sensor set ultimo_sinal_em = now() - interval '5 minutes' where id = $1`, [
        supino.sensor_id,
      ]);
      await sensorInforma(c, supino.sensor_id, 'livre');
      const atraso = await valor(
        c,
        `select extract(epoch from (now() - ultimo_sinal_em)) from telemetria.sensor where id = $1`,
        [supino.sensor_id]
      );
      assert.ok(atraso < 30, `o último sinal deveria ser de agora, mas tem ${atraso} s`);
    });

    it('durante a espera após o aviso de livre o aparelho continua ocupado', async () => {
      await sensorInforma(c, supino.sensor_id, 'ocupado');
      await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(await estadoDe(c, supino.equipamento_id), 'ocupado');
    });

    it('voltar a ocupado dentro da espera retoma a mesma sessão (descanso entre séries)', async () => {
      const primeira = await sensorInforma(c, supino.sensor_id, 'ocupado');
      await sensorInforma(c, supino.sensor_id, 'livre');
      const retomada = await sensorInforma(c, supino.sensor_id, 'ocupado');

      assert.equal(retomada.sessao_id, primeira.sessao_id);
      assert.equal(await valor(c, 'select count(*)::int from telemetria.sessao_uso'), 1);
      const sessao = await uma(c, 'select fim_em, encerrada_por from telemetria.sessao_uso');
      assert.equal(sessao.fim_em, null);
      assert.equal(sessao.encerrada_por, null);
    });

    it('depois de passada a espera o aparelho fica livre e a próxima ocupação abre outra sessão', async () => {
      const primeira = await sensorInforma(c, supino.sensor_id, 'ocupado');
      await sensorInforma(c, supino.sensor_id, 'livre');
      await c.query(
        `update telemetria.sessao_uso
            set inicio_em = now() - interval '10 minutes', fim_em = now() - interval '5 minutes'
          where id = $1`,
        [primeira.sessao_id]
      );
      assert.equal(await estadoDe(c, supino.equipamento_id), 'livre');

      const segunda = await sensorInforma(c, supino.sensor_id, 'ocupado');
      assert.notEqual(segunda.sessao_id, primeira.sessao_id);
      assert.equal(await valor(c, 'select count(*)::int from telemetria.sessao_uso'), 2);
    });

    it('a espera vem da academia: com zero segundos o aparelho fica livre na hora', async () => {
      await c.query(`update core.academia set segundos_espera_para_livre = 0 where id = $1`, [supino.academia_id]);
      await sensorInforma(c, supino.sensor_id, 'ocupado');
      const resposta = await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(resposta.espera_segundos, 0);
      assert.equal(await estadoDe(c, supino.equipamento_id), 'livre');
    });

    it('a resposta ao sensor traz a configuração que ele deve usar', async () => {
      const resposta = await sensorInforma(c, supino.sensor_id, 'livre');
      assert.equal(resposta.espera_segundos, 120);
      assert.equal(resposta.batimento_segundos, 60);
      assert.equal(resposta.estado_registrado, 'livre');
    });

    it('ao voltar de um silêncio, a sessão antiga termina onde o sensor foi ouvido pela última vez', async () => {
      const antiga = await sensorInforma(c, supino.sensor_id, 'ocupado');
      await c.query(`update telemetria.sessao_uso set inicio_em = now() - interval '30 minutes' where id = $1`, [
        antiga.sessao_id,
      ]);
      await c.query(`update telemetria.sensor set ultimo_sinal_em = now() - interval '20 minutes' where id = $1`, [
        supino.sensor_id,
      ]);

      const nova = await sensorInforma(c, supino.sensor_id, 'ocupado');
      assert.notEqual(nova.sessao_id, antiga.sessao_id, 'o tempo calado não pode continuar contando como uso');

      const velha = await uma(c, 'select encerrada_por, duracao_segundos from telemetria.sessao_uso where id = $1', [
        antiga.sessao_id,
      ]);
      assert.equal(velha.encerrada_por, 'sem_sinal');
      assert.ok(velha.duracao_segundos >= 598 && velha.duracao_segundos <= 604, `veio ${velha.duracao_segundos}`);

      const leitura = await uma(
        c,
        'select sem_sinal_desde, recebido_em from telemetria.leitura_sensor order by id desc limit 1'
      );
      assert.ok(leitura.sem_sinal_desde < leitura.recebido_em, 'a volta do silêncio precisa ficar registrada');
    });

    it('recusa sensor inexistente, sensor desativado e estado inválido', async () => {
      await assert.rejects(sensorInforma(c, 999999, 'livre'), (erro) => erro.code === 'P0002');

      await c.query(`update telemetria.sensor set ativo = false, desativado_em = now() where id = $1`, [
        supino.sensor_id,
      ]);
      await assert.rejects(sensorInforma(c, supino.sensor_id, 'livre'), (erro) => erro.code === 'P0002');

      const outro = await aparelho(c, CENTRO, 'Supino Inclinado 1');
      await assert.rejects(sensorInforma(c, outro.sensor_id, 'quebrado'), (erro) => erro.code === '22023');
      await assert.rejects(sensorInforma(c, outro.sensor_id, null), (erro) => erro.code === '22023');
    });

    it('o banco não deixa existirem duas sessões abertas no mesmo aparelho', async () => {
      await sensorInforma(c, supino.sensor_id, 'ocupado');
      await assert.rejects(
        c.query(
          `insert into telemetria.sessao_uso (academia_id, equipamento_id, inicio_em) values ($1, $2, now())`,
          [supino.academia_id, supino.equipamento_id]
        ),
        (erro) => erro.code === '23505'
      );
    });

    it('duas mensagens ao mesmo tempo do mesmo sensor não duplicam a sessão', async () => {
      const { urlTeste } = configurarTeste();
      const conexoes = [];
      for (let i = 0; i < 4; i += 1) {
        const extra = criarCliente(urlTeste);
        await extra.connect();
        conexoes.push(extra);
      }
      try {
        await Promise.all(
          Array.from({ length: 12 }, (_, i) => sensorInforma(conexoes[i % conexoes.length], supino.sensor_id, 'ocupado'))
        );
      } finally {
        await Promise.all(conexoes.map((x) => x.end()));
      }
      assert.equal(await valor(c, 'select count(*)::int from telemetria.sessao_uso'), 1);
      assert.equal(await valor(c, 'select count(*)::int from telemetria.leitura_sensor'), 1);
    });

    it('apagar a conta de uma pessoa remove os dados dela, mas o uso dos aparelhos continua sem ligação com ela', async () => {
      const carlos = await uma(
        c,
        `select u.id as usuario_id from core.usuario u join core.conta co on co.id = u.conta_id
          where co.email = 'carlos@exemplo.com'`
      );
      await c.query(
        `insert into telemetria.sessao_uso (academia_id, equipamento_id, usuario_id, inicio_em, fim_em, encerrada_por)
         values ($1, $2, $3, now() - interval '20 minutes', now() - interval '10 minutes', 'sensor')`,
        [supino.academia_id, supino.equipamento_id, carlos.usuario_id]
      );
      await c.query(`insert into core.checkin (usuario_id, academia_id) values ($1, $2)`, [
        carlos.usuario_id,
        supino.academia_id,
      ]);
      assert.ok((await valor(c, 'select count(*)::int from core.plano_treino where usuario_id = $1', [carlos.usuario_id])) > 0);

      await c.query(`delete from core.conta where email = 'carlos@exemplo.com'`);

      assert.equal(await valor(c, `select count(*)::int from core.conta where email = 'carlos@exemplo.com'`), 0);
      assert.equal(await valor(c, 'select count(*)::int from core.usuario where id = $1', [carlos.usuario_id]), 0);
      assert.equal(await valor(c, 'select count(*)::int from core.plano_treino where usuario_id = $1', [carlos.usuario_id]), 0);
      assert.equal(await valor(c, 'select count(*)::int from core.checkin where usuario_id = $1', [carlos.usuario_id]), 0);
      assert.equal(await valor(c, 'select count(*)::int from core.matricula where usuario_id = $1', [carlos.usuario_id]), 0);

      const sessao = await uma(c, 'select usuario_id from telemetria.sessao_uso');
      assert.equal(sessao.usuario_id, null, 'a sessão de uso fica, sem ligação com a pessoa');
    });
  });

  describe('isolamento entre academias', () => {
    it('sensor de uma academia não pode ficar preso a aparelho de outra', async () => {
      // Aparelho novo da Norte, ainda sem sensor, para que a única falha possível seja a mistura de academias.
      const tipo = await valor(c, `select id from core.tipo_equipamento where codigo = 'esteira'`);
      const aparelhoNorte = await uma(
        c,
        `insert into core.equipamento (academia_id, tipo_equipamento_id, nome)
         values ((select id from core.academia where nome = $1), $2, 'Esteira nova da Norte') returning id`,
        [NORTE, tipo]
      );
      await assert.rejects(
        c.query(
          `insert into telemetria.sensor (academia_id, equipamento_id, tipo, chave_hash)
           values ($1, $2, 'corrente', sha256(convert_to('qualquer', 'UTF8')))`,
          [supino.academia_id, aparelhoNorte.id]
        ),
        (erro) => erro.code === '23503'
      );
    });

    it('sessão de uso não pode misturar aparelho de uma academia com outra', async () => {
      const aparelhoNorte = await aparelho(c, NORTE, 'Supino Inclinado 1');
      await assert.rejects(
        c.query(
          `insert into telemetria.sessao_uso (academia_id, equipamento_id, inicio_em) values ($1, $2, now())`,
          [supino.academia_id, aparelhoNorte.equipamento_id]
        ),
        (erro) => erro.code === '23503'
      );
    });

    it('o papel de dono vale só para a academia em que foi dado', async () => {
      const donos = await linhas(
        c,
        `select a.nome as academia, co.email
           from core.conta_papel cp
           join core.papel p on p.id = cp.papel_id and p.codigo = 'dono'
           join core.academia a on a.id = cp.academia_id
           join core.conta co on co.id = cp.conta_id
          order by a.nome`
      );
      assert.deepEqual(donos, [
        { academia: CENTRO, email: 'dono.centro@exemplo.com' },
        { academia: NORTE, email: 'dono.norte@exemplo.com' },
      ]);
    });
  });

  describe('leitura_sensor dividida por mês', () => {
    it('cria a partição de um mês que ainda não existe e é seguro chamar de novo', async () => {
      const nome = await valor(c, `select telemetria.garantir_particao_leitura('2025-03-15 12:00:00-03')`);
      assert.equal(nome, 'leitura_sensor_2025_03');
      const repetido = await valor(c, `select telemetria.garantir_particao_leitura('2025-03-20 12:00:00-03')`);
      assert.equal(repetido, nome);
    });

    it('a divisa entre meses segue o calendário de São Paulo', async () => {
      await c.query(`select telemetria.garantir_particao_leitura('2025-02-10 12:00:00-03')`);
      await c.query(`select telemetria.garantir_particao_leitura('2025-03-10 12:00:00-03')`);
      const base = [supino.sensor_id, supino.academia_id, supino.equipamento_id];

      // 1o de março de 2025 às 00:00 em São Paulo (03:00 UTC) já é março.
      const marco = await uma(
        c,
        `insert into telemetria.leitura_sensor (sensor_id, academia_id, equipamento_id, recebido_em, estado, mudou_estado)
         values ($1, $2, $3, '2025-03-01 00:00:00-03', 'livre', true) returning tableoid::regclass::text as particao`,
        base
      );
      assert.equal(marco.particao, 'telemetria.leitura_sensor_2025_03');

      // Um segundo antes ainda é fevereiro, mesmo que em UTC já fosse 1o de março.
      const fevereiro = await uma(
        c,
        `insert into telemetria.leitura_sensor (sensor_id, academia_id, equipamento_id, recebido_em, estado, mudou_estado)
         values ($1, $2, $3, '2025-02-28 23:59:59-03', 'ocupado', true) returning tableoid::regclass::text as particao`,
        base
      );
      assert.equal(fevereiro.particao, 'telemetria.leitura_sensor_2025_02');
    });

    it('recusa leitura sem motivo para existir (nem mudou, nem voltou de silêncio)', async () => {
      await assert.rejects(
        c.query(
          `insert into telemetria.leitura_sensor (sensor_id, academia_id, equipamento_id, estado, mudou_estado)
           values ($1, $2, $3, 'livre', false)`,
          [supino.sensor_id, supino.academia_id, supino.equipamento_id]
        ),
        (erro) => erro.code === '23514'
      );
    });

    it('a gravação da leitura recria a partição do mês atual se ela tiver sumido, sem perder a leitura', async () => {
      const mes = await valor(c, `select to_char(now() at time zone 'America/Sao_Paulo', 'YYYY_MM')`);
      const nome = `leitura_sensor_${mes}`;
      await c.query(`drop table telemetria.${nome}`);
      assert.equal(await valor(c, `select to_regclass('telemetria.${nome}') is not null`), false);

      await sensorInforma(c, supino.sensor_id, 'ocupado');

      assert.equal(await valor(c, `select to_regclass('telemetria.${nome}') is not null`), true);
      assert.equal(await valor(c, 'select count(*)::int from telemetria.leitura_sensor'), 1);
    });

    it('a rotina que garante partições cria o mês atual e os seguintes', async () => {
      const nomes = await valor(c, 'select telemetria.garantir_particoes_leitura(4)');
      assert.equal(nomes.length, 5);
      assert.ok(nomes.every((n) => /^leitura_sensor_\d{4}_\d{2}$/.test(n)));
    });
  });
});
