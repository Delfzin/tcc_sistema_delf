'use strict';

// Tudo o que é preciso para abrir uma conexão com o PostgreSQL.
// Usado pela API, pelo executor de migrações e pelos testes.

const fs = require('node:fs');
const { Client, Pool, types } = require('pg');

// O PostgreSQL devolve bigint e numeric como texto, porque podem ser maiores
// do que o JavaScript consegue guardar com exatidão. Os números do DELF
// (identificadores, contagens, segundos) são pequenos, então convertemos
// para número comum. Sem isto o site receberia "id": "12" em vez de "id": 12.
types.setTypeParser(20, (valor) => Number(valor)); // bigint
types.setTypeParser(1700, (valor) => parseFloat(valor)); // numeric

const HOSTS_LOCAIS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);

function hostDaUrl(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return '';
  }
}

function ehLocal(url) {
  return HOSTS_LOCAIS.has(hostDaUrl(url));
}

// DATABASE_SSL controla a criptografia da conexão:
//   auto           desligado em localhost, ligado e verificado em qualquer outro endereço
//   ligado         criptografa e confere o certificado do servidor (recomendado na nuvem)
//   sem-verificar  criptografa mas NÃO confere quem está do outro lado (mais fraco, só se necessário)
//   desligado      sem criptografia (somente para o próprio computador)
function opcoesSsl(url, env = process.env) {
  const modo = (env.DATABASE_SSL || 'auto').trim().toLowerCase();
  if (modo === 'desligado') return false;
  if (modo === 'auto' && ehLocal(url)) return false;
  if (modo === 'sem-verificar') return { rejectUnauthorized: false };
  if (modo === 'ligado' || modo === 'auto') {
    const ssl = { rejectUnauthorized: true };
    if (env.DATABASE_SSL_CA) ssl.ca = fs.readFileSync(env.DATABASE_SSL_CA, 'utf8');
    return ssl;
  }
  throw new Error(
    `DATABASE_SSL com valor desconhecido: "${modo}". Use auto, ligado, sem-verificar ou desligado.`
  );
}

// Tira da URL os parâmetros de SSL (sslmode, ssl). Se ficassem, o pacote "pg"
// os usaria no lugar da nossa configuração e a regra acima deixaria de valer.
function urlSemParametrosDeSsl(url) {
  const u = new URL(url);
  u.searchParams.delete('sslmode');
  u.searchParams.delete('ssl');
  return u.toString();
}

function opcoesDeConexao(url, env = process.env) {
  if (!url) {
    throw new Error('Falta o endereço do banco. Preencha o arquivo .env (veja .env.example).');
  }
  return { connectionString: urlSemParametrosDeSsl(url), ssl: opcoesSsl(url, env) };
}

function criarCliente(url, env = process.env) {
  return new Client(opcoesDeConexao(url, env));
}

function criarPool(url, env = process.env, extra = {}) {
  return new Pool({ ...opcoesDeConexao(url, env), ...extra });
}

// Troca só o nome do banco na URL. Usado para apontar para "delf_teste".
function urlComOutroBanco(url, nomeDoBanco) {
  const u = new URL(url);
  u.pathname = `/${nomeDoBanco}`;
  return u.toString();
}

module.exports = {
  criarCliente,
  criarPool,
  ehLocal,
  hostDaUrl,
  opcoesDeConexao,
  opcoesSsl,
  urlComOutroBanco,
  urlSemParametrosDeSsl,
};
