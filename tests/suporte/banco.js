'use strict';

// Apoio comum aos testes que conversam com o banco de teste ("delf_teste").
// O banco é criado do zero por "npm test" (scripts/preparar-banco-de-teste.js).

const { carregarEnv } = require('../../src/env');
const { criarCliente } = require('../../src/conexao');
const { configurarTeste } = require('../../scripts/lib/banco-de-teste');
const { aplicarSeed, apagarDadosDeTeste } = require('../../scripts/lib/semente');

carregarEnv();

async function conectar() {
  const { urlTeste } = configurarTeste();
  const cliente = criarCliente(urlTeste);
  await cliente.connect();
  return cliente;
}

// Volta os dados de pessoas, academias e telemetria ao estado do seed.
// Cada arquivo de teste chama isto no começo, para não depender de outro.
async function reiniciarDados(cliente) {
  await apagarDadosDeTeste(cliente);
  await aplicarSeed(cliente);
}

async function linhas(cliente, sql, parametros = []) {
  const { rows } = await cliente.query(sql, parametros);
  return rows;
}

async function uma(cliente, sql, parametros = []) {
  const { rows } = await cliente.query(sql, parametros);
  return rows[0];
}

async function valor(cliente, sql, parametros = []) {
  const linha = await uma(cliente, sql, parametros);
  return linha ? Object.values(linha)[0] : undefined;
}

// Busca o identificador de um aparelho pelo nome da academia e do aparelho.
async function aparelho(cliente, nomeAcademia, nomeAparelho) {
  return uma(
    cliente,
    `select e.id as equipamento_id, e.academia_id, s.id as sensor_id
       from core.equipamento e
       join core.academia a on a.id = e.academia_id
       join telemetria.sensor s on s.equipamento_id = e.id and s.ativo
      where a.nome = $1 and e.nome = $2`,
    [nomeAcademia, nomeAparelho]
  );
}

// O sensor fala com o banco.
async function sensorInforma(cliente, sensorId, estado) {
  return uma(cliente, 'select * from telemetria.registrar_leitura($1, $2)', [sensorId, estado]);
}

async function estadoDe(cliente, equipamentoId) {
  return valor(cliente, 'select estado from core.vw_estado_equipamento where equipamento_id = $1', [equipamentoId]);
}

module.exports = {
  aparelho,
  conectar,
  estadoDe,
  linhas,
  reiniciarDados,
  sensorInforma,
  uma,
  valor,
};
