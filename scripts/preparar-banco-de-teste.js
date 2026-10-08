'use strict';

// Roda antes dos testes ("npm test"): recria o banco "delf_teste" do zero,
// aplica todas as migrações e carrega os dados de teste.

const { carregarEnv } = require('../src/env');
const { criarCliente } = require('../src/conexao');
const { aplicarPendentes } = require('./lib/migracoes');
const { aplicarSeed } = require('./lib/semente');
const { configurarTeste, NOME_PADRAO, recriarBanco } = require('./lib/banco-de-teste');

carregarEnv();

async function principal() {
  const { urlAdmin, urlTeste } = configurarTeste();
  await recriarBanco(urlAdmin, NOME_PADRAO);

  const cliente = criarCliente(urlTeste);
  await cliente.connect();
  try {
    const aplicadas = await aplicarPendentes(cliente);
    await aplicarSeed(cliente);
    console.log(
      `Banco de teste "${NOME_PADRAO}" pronto: ${aplicadas.length} migrações e dados de teste carregados.`
    );
  } finally {
    await cliente.end();
  }
}

principal().catch((erro) => {
  console.error(`Erro ao preparar o banco de teste: ${erro.message}`);
  process.exit(1);
});
