'use strict';

// Apoio para criar e apagar os bancos usados SÓ pelos testes.
//
// Os testes apagam e recriam bancos inteiros. Por isso há três travas:
//   1. o nome do banco precisa começar com "delf_teste";
//   2. o servidor precisa ser o do próprio computador (localhost);
//   3. o endereço vem de DATABASE_URL_TESTE, nunca de DATABASE_URL.

const { criarCliente, ehLocal, urlComOutroBanco } = require('../../src/conexao');

const NOME_PADRAO = 'delf_teste';
const PADRAO_NOME = /^delf_teste[a-z0-9_]*$/;

function configurarTeste(env = process.env) {
  const urlAdmin = env.DATABASE_URL_TESTE;
  if (!urlAdmin) {
    throw new Error(
      'Falta DATABASE_URL_TESTE. Preencha no arquivo .env o endereço de um PostgreSQL do SEU computador, ' +
        'com um usuário que possa criar bancos (veja .env.example).'
    );
  }
  if (!ehLocal(urlAdmin) && env.DELF_TESTE_PERMITIR_HOST_REMOTO !== 'sim') {
    throw new Error(
      'DATABASE_URL_TESTE aponta para um servidor que não é o seu computador. ' +
        'Os testes apagam e recriam bancos, então só rodam em PostgreSQL local.'
    );
  }
  return { urlAdmin, urlTeste: urlComOutroBanco(urlAdmin, NOME_PADRAO) };
}

async function recriarBanco(urlAdmin, nome) {
  if (!PADRAO_NOME.test(nome)) {
    throw new Error(`Nome de banco de teste inválido: "${nome}". Precisa começar com "delf_teste".`);
  }
  const admin = criarCliente(urlAdmin);
  await admin.connect();
  try {
    await admin.query(`drop database if exists "${nome}" with (force)`);
    await admin.query(`create database "${nome}"`);
  } finally {
    await admin.end();
  }
}

async function apagarBanco(urlAdmin, nome) {
  if (!PADRAO_NOME.test(nome)) {
    throw new Error(`Nome de banco de teste inválido: "${nome}". Precisa começar com "delf_teste".`);
  }
  const admin = criarCliente(urlAdmin);
  await admin.connect();
  try {
    await admin.query(`drop database if exists "${nome}" with (force)`);
  } finally {
    await admin.end();
  }
}

module.exports = { apagarBanco, configurarTeste, NOME_PADRAO, recriarBanco };
