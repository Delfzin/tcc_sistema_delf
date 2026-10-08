'use strict';

// Guarda e confere senhas usando scrypt, que já vem dentro do Node.
//
// Por que não guardar a senha como o aluno digitou: se o banco vazar, quem o
// lê não pode descobrir a senha. O scrypt é uma conta propositalmente lenta e
// gulosa em memória, o que torna cada tentativa de adivinhar cara para quem
// ataca.
//
// Formato guardado na coluna core.conta.senha_hash:
//   scrypt$N$r$p$sal$resultado
// Os parâmetros ficam junto do texto, então dá para aumentá-los no futuro sem
// invalidar as senhas antigas.

const crypto = require('node:crypto');
const { promisify } = require('node:util');

const scrypt = promisify(crypto.scrypt);

const PARAMETROS = { N: 32768, r: 8, p: 1 };
const TAMANHO_DA_CHAVE = 64;
const TAMANHO_DO_SAL = 16;

function memoriaNecessaria({ N, r }) {
  // O scrypt usa cerca de 128 * N * r bytes. Damos o dobro de folga.
  return 128 * N * r * 2;
}

function normalizar(senha) {
  return String(senha).normalize('NFKC');
}

async function gerarHash(senha, parametros = PARAMETROS) {
  const sal = crypto.randomBytes(TAMANHO_DO_SAL);
  const chave = await scrypt(normalizar(senha), sal, TAMANHO_DA_CHAVE, {
    N: parametros.N,
    r: parametros.r,
    p: parametros.p,
    maxmem: memoriaNecessaria(parametros),
  });
  return [
    'scrypt',
    parametros.N,
    parametros.r,
    parametros.p,
    sal.toString('base64url'),
    chave.toString('base64url'),
  ].join('$');
}

function lerHash(hashGuardado) {
  if (typeof hashGuardado !== 'string') return null;
  const partes = hashGuardado.split('$');
  if (partes.length !== 6 || partes[0] !== 'scrypt') return null;
  const [, N, r, p, sal, resultado] = partes;
  const numeros = { N: Number(N), r: Number(r), p: Number(p) };
  if (!Object.values(numeros).every((n) => Number.isInteger(n) && n > 0)) return null;
  return {
    ...numeros,
    sal: Buffer.from(sal, 'base64url'),
    resultado: Buffer.from(resultado, 'base64url'),
  };
}

async function conferirSenha(senha, hashGuardado) {
  const lido = lerHash(hashGuardado);
  if (!lido) return false;
  const chave = await scrypt(normalizar(senha), lido.sal, lido.resultado.length, {
    N: lido.N,
    r: lido.r,
    p: lido.p,
    maxmem: memoriaNecessaria(lido),
  });
  return crypto.timingSafeEqual(chave, lido.resultado);
}

// Diz se o hash foi feito com parâmetros mais fracos que os atuais.
// Quando for verdade, o login pode gravar um hash novo.
function precisaAtualizar(hashGuardado) {
  const lido = lerHash(hashGuardado);
  if (!lido) return true;
  return lido.N < PARAMETROS.N || lido.r < PARAMETROS.r || lido.p < PARAMETROS.p;
}

module.exports = { gerarHash, conferirSenha, precisaAtualizar, PARAMETROS };
