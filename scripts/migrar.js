'use strict';

// Aplica as migrações pendentes no banco.
//
//   npm run migrar              aplica o que falta
//   npm run migrar -- --status  só mostra o que já foi aplicado e o que falta
//
// Usa DATABASE_URL_MIGRACAO (ou DATABASE_URL, se a primeira não existir).
// Esse endereço precisa ter permissão de criar tabelas.

const { carregarEnv } = require('../src/env');
const { criarCliente } = require('../src/conexao');
const { aplicarPendentes, jaAplicadas, listarArquivos } = require('./lib/migracoes');

carregarEnv();

async function principal() {
  const somenteStatus = process.argv.includes('--status');
  const url = process.env.DATABASE_URL_MIGRACAO || process.env.DATABASE_URL;

  if (process.env.DELF_AMBIENTE === 'producao' && !process.argv.includes('--confirmo-producao')) {
    throw new Error(
      'DELF_AMBIENTE está como "producao". Confirme rodando: npm run migrar -- --confirmo-producao'
    );
  }

  const cliente = criarCliente(url);
  await cliente.connect();
  try {
    if (somenteStatus) {
      const arquivos = await listarArquivos();
      const aplicadas = await jaAplicadas(cliente);
      for (const arquivo of arquivos) {
        console.log(`${aplicadas.has(arquivo) ? 'aplicada ' : 'pendente '} ${arquivo}`);
      }
      return;
    }
    const feitas = await aplicarPendentes(cliente, { log: console.log });
    console.log(
      feitas.length === 0
        ? 'Nada a fazer: o banco já está com todas as migrações.'
        : `Pronto: ${feitas.length} migração(ões) aplicada(s).`
    );
  } finally {
    await cliente.end();
  }
}

principal().catch((erro) => {
  console.error(`Erro: ${erro.message}`);
  process.exit(1);
});
