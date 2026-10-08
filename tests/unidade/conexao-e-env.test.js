'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { lerLinhas } = require('../../src/env');
const {
  ehLocal,
  opcoesDeConexao,
  opcoesSsl,
  urlComOutroBanco,
  urlSemParametrosDeSsl,
} = require('../../src/conexao');
const { configurarTeste } = require('../../scripts/lib/banco-de-teste');

describe('leitura do arquivo .env', () => {
  it('lê chave=valor, ignora comentários e linhas vazias e tira aspas', () => {
    const lido = lerLinhas(
      ['# comentário', '', 'A=1', 'B = dois ', 'C="com aspas"', "D='simples'", 'sem-igual', '=semchave'].join('\n')
    );
    assert.deepEqual(lido, { A: '1', B: 'dois', C: 'com aspas', D: 'simples' });
  });

  it('aceita fim de linha do Windows', () => {
    assert.deepEqual(lerLinhas('A=1\r\nB=2\r\n'), { A: '1', B: '2' });
  });

  it('mantém o sinal de igual dentro do valor (como nas senhas e endereços)', () => {
    assert.deepEqual(lerLinhas('URL=postgres://u:p=q@h/b?x=1'), { URL: 'postgres://u:p=q@h/b?x=1' });
  });
});

describe('conexão com o banco', () => {
  it('reconhece endereços do próprio computador', () => {
    assert.equal(ehLocal('postgres://u:p@localhost:5432/b'), true);
    assert.equal(ehLocal('postgres://u:p@127.0.0.1:5432/b'), true);
    assert.equal(ehLocal('postgres://u:p@db.exemplo.com:5432/b'), false);
  });

  it('SSL automático: desligado no computador local, ligado e verificado em endereço remoto', () => {
    assert.equal(opcoesSsl('postgres://u:p@localhost/b', {}), false);
    assert.deepEqual(opcoesSsl('postgres://u:p@db.exemplo.com/b', {}), { rejectUnauthorized: true });
  });

  it('SSL pode ser forçado nos quatro modos', () => {
    const remoto = 'postgres://u:p@db.exemplo.com/b';
    assert.equal(opcoesSsl(remoto, { DATABASE_SSL: 'desligado' }), false);
    assert.deepEqual(opcoesSsl(remoto, { DATABASE_SSL: 'sem-verificar' }), { rejectUnauthorized: false });
    assert.deepEqual(opcoesSsl('postgres://u:p@localhost/b', { DATABASE_SSL: 'ligado' }), { rejectUnauthorized: true });
    assert.deepEqual(opcoesSsl(remoto, { DATABASE_SSL: 'ligado' }), { rejectUnauthorized: true });
  });

  it('recusa um modo de SSL desconhecido', () => {
    assert.throws(() => opcoesSsl('postgres://u:p@h/b', { DATABASE_SSL: 'talvez' }), /valor desconhecido/);
  });

  it('tira sslmode da URL, para a nossa configuração de SSL sempre valer', () => {
    const limpa = urlSemParametrosDeSsl('postgres://u:p@h:5432/b?sslmode=require&application_name=delf');
    assert.ok(!limpa.includes('sslmode'));
    assert.ok(limpa.includes('application_name=delf'));
  });

  it('opcoesDeConexao exige o endereço do banco', () => {
    assert.throws(() => opcoesDeConexao(undefined), /Falta o endereço do banco/);
    assert.throws(() => opcoesDeConexao(''), /Falta o endereço do banco/);
  });

  it('troca só o nome do banco na URL', () => {
    assert.equal(
      urlComOutroBanco('postgres://u:p@127.0.0.1:5432/postgres', 'delf_teste'),
      'postgres://u:p@127.0.0.1:5432/delf_teste'
    );
  });
});

describe('travas do banco de teste', () => {
  it('exige DATABASE_URL_TESTE', () => {
    assert.throws(() => configurarTeste({}), /Falta DATABASE_URL_TESTE/);
  });

  it('recusa servidor que não é o computador local', () => {
    assert.throws(
      () => configurarTeste({ DATABASE_URL_TESTE: 'postgres://u:p@db.exemplo.com:5432/postgres' }),
      /não é o seu computador/
    );
  });

  it('aceita servidor local e aponta para o banco delf_teste', () => {
    const { urlTeste } = configurarTeste({ DATABASE_URL_TESTE: 'postgres://u:p@localhost:5432/postgres' });
    assert.ok(urlTeste.endsWith('/delf_teste'));
  });
});
