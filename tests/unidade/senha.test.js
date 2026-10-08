'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { gerarHash, conferirSenha, precisaAtualizar, PARAMETROS } = require('../../src/seguranca/senha');

describe('senha com scrypt', () => {
  it('guarda no formato scrypt$N$r$p$sal$resultado e não contém a senha', async () => {
    const hash = await gerarHash('minha senha 123');
    const partes = hash.split('$');
    assert.equal(partes.length, 6);
    assert.equal(partes[0], 'scrypt');
    assert.equal(Number(partes[1]), PARAMETROS.N);
    assert.ok(!hash.includes('minha senha 123'));
  });

  it('confere a senha certa e recusa a errada', async () => {
    const hash = await gerarHash('delf1234');
    assert.equal(await conferirSenha('delf1234', hash), true);
    assert.equal(await conferirSenha('delf12345', hash), false);
    assert.equal(await conferirSenha('', hash), false);
  });

  it('a mesma senha gera resumos diferentes, porque o sal muda', async () => {
    const a = await gerarHash('igual');
    const b = await gerarHash('igual');
    assert.notEqual(a, b);
    assert.equal(await conferirSenha('igual', a), true);
    assert.equal(await conferirSenha('igual', b), true);
  });

  it('trata como iguais as duas formas de escrever uma letra acentuada', async () => {
    const hash = await gerarHash('senhação'); // "senhação" com letras compostas
    assert.equal(await conferirSenha('senhação', hash), true); // c + cedilha e a + til soltos
  });

  it('recusa resumo malformado em vez de quebrar', async () => {
    assert.equal(await conferirSenha('x', 'texto qualquer'), false);
    assert.equal(await conferirSenha('x', 'scrypt$a$b$c$d$e'), false);
    assert.equal(await conferirSenha('x', null), false);
    assert.equal(await conferirSenha('x', undefined), false);
  });

  it('avisa quando o resumo foi feito com parâmetros mais fracos que os atuais', async () => {
    const fraco = await gerarHash('x', { N: 1024, r: 8, p: 1 });
    assert.equal(precisaAtualizar(fraco), true);
    assert.equal(await conferirSenha('x', fraco), true, 'o resumo antigo continua válido');
    assert.equal(precisaAtualizar(await gerarHash('x')), false);
  });
});
