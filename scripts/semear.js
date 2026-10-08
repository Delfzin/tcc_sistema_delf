'use strict';

// Carrega os dados de TESTE (supabase/seed.sql) no banco.
//
//   npm run semear                 carrega os dados de teste num banco que ainda não os tem
//   npm run semear -- --recomecar  apaga os dados de teste e carrega de novo
//
// Recusa rodar quando DELF_AMBIENTE=producao. O próprio seed.sql também recusa
// quando o banco tem alguma academia que não seja de teste.

const { carregarEnv } = require('../src/env');
const { criarCliente } = require('../src/conexao');
const { aplicarSeed, apagarDadosDeTeste } = require('./lib/semente');

carregarEnv();

async function principal() {
  if (process.env.DELF_AMBIENTE === 'producao') {
    throw new Error('Recusado: DELF_AMBIENTE está como "producao". Dados de teste nunca entram em produção.');
  }

  const url = process.env.DATABASE_URL_MIGRACAO || process.env.DATABASE_URL;
  const cliente = criarCliente(url);
  await cliente.connect();
  try {
    if (process.argv.includes('--recomecar')) {
      await apagarDadosDeTeste(cliente);
      console.log('Dados de teste anteriores apagados.');
    }
    await aplicarSeed(cliente);
    console.log('Dados de teste carregados.');
    console.log('Conta de aluno: carlos@exemplo.com  senha: delf1234');
    console.log('Conta de dono:  dono.centro@exemplo.com  senha: delf1234');
  } finally {
    await cliente.end();
  }
}

principal().catch((erro) => {
  console.error(`Erro: ${erro.message}`);
  process.exit(1);
});
