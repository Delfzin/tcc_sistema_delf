'use strict';

// Carrega o arquivo ".env" (se existir) para dentro de process.env.
// Existe para não precisarmos instalar o pacote "dotenv": são poucas linhas
// e funcionam em qualquer versão do Node.
//
// Regras:
//   - linhas vazias e linhas que começam com # são ignoradas;
//   - formato CHAVE=valor, com ou sem aspas em volta do valor;
//   - uma variável que já existe no ambiente NÃO é sobrescrita, para que o
//     valor definido no servidor de publicação sempre vença o arquivo.

const fs = require('node:fs');
const path = require('node:path');

function lerLinhas(texto) {
  const resultado = {};
  for (const linhaBruta of texto.split(/\r?\n/)) {
    const linha = linhaBruta.trim();
    if (linha === '' || linha.startsWith('#')) continue;
    const posicaoIgual = linha.indexOf('=');
    if (posicaoIgual < 1) continue;
    const chave = linha.slice(0, posicaoIgual).trim();
    let valor = linha.slice(posicaoIgual + 1).trim();
    const aspas = valor[0];
    if ((aspas === '"' || aspas === "'") && valor.endsWith(aspas) && valor.length >= 2) {
      valor = valor.slice(1, -1);
    }
    resultado[chave] = valor;
  }
  return resultado;
}

function carregarEnv(arquivo = path.join(__dirname, '..', '.env')) {
  let texto;
  try {
    texto = fs.readFileSync(arquivo, 'utf8');
  } catch (erro) {
    if (erro.code === 'ENOENT') return false;
    throw erro;
  }
  for (const [chave, valor] of Object.entries(lerLinhas(texto))) {
    if (process.env[chave] === undefined) process.env[chave] = valor;
  }
  return true;
}

module.exports = { carregarEnv, lerLinhas };
