'use strict';

// Lógica de aplicar as migrações de supabase/migrations em ordem.
// Usada por "npm run migrar" e pelo preparo do banco de teste.

const fs = require('node:fs/promises');
const path = require('node:path');

const PASTA_MIGRACOES = path.join(__dirname, '..', '..', 'supabase', 'migrations');
const PADRAO_ARQUIVO = /^(\d{4})_[a-z0-9_]+\.sql$/;

async function listarArquivos(pasta = PASTA_MIGRACOES) {
  const nomes = (await fs.readdir(pasta)).filter((nome) => nome.endsWith('.sql')).sort();

  const vistos = new Set();
  for (const nome of nomes) {
    const partes = PADRAO_ARQUIVO.exec(nome);
    if (!partes) {
      throw new Error(
        `O arquivo "${nome}" não segue o padrão NNNN_nome_em_minusculas.sql (por exemplo 0010_painel.sql).`
      );
    }
    if (vistos.has(partes[1])) {
      throw new Error(`Dois arquivos de migração usam o número ${partes[1]}. Cada número só pode aparecer uma vez.`);
    }
    vistos.add(partes[1]);
  }
  return nomes;
}

async function jaAplicadas(cliente) {
  const existe = await cliente.query(`select to_regclass('core.migracao_aplicada') as tabela`);
  if (!existe.rows[0].tabela) return new Set();
  const { rows } = await cliente.query('select arquivo from core.migracao_aplicada');
  return new Set(rows.map((linha) => linha.arquivo));
}

async function bancoTemTabelasSemControle(cliente) {
  const { rows } = await cliente.query(`
    select count(*)::int as total
      from information_schema.tables
     where table_schema in ('core', 'telemetria')
  `);
  return rows[0].total > 0;
}

function linhaDoErro(sql, erro) {
  const posicao = Number(erro.position);
  if (!Number.isFinite(posicao) || posicao < 1) return null;
  return sql.slice(0, posicao).split('\n').length;
}

// Aplica, em ordem, as migrações que ainda não foram aplicadas.
// Cada arquivo roda dentro de uma transação: se algo falhar, aquele arquivo
// inteiro é desfeito e nada fica pela metade.
async function aplicarPendentes(cliente, { log = () => {}, pasta = PASTA_MIGRACOES } = {}) {
  const arquivos = await listarArquivos(pasta);
  const aplicadas = await jaAplicadas(cliente);

  if (aplicadas.size === 0 && (await bancoTemTabelasSemControle(cliente))) {
    throw new Error(
      'Este banco já tem tabelas, mas não tem o registro de migrações aplicadas. ' +
        'Isso acontece quando o banco foi montado colando os arquivos no editor SQL sem a primeira migração. ' +
        'Não rode o executor aqui: use um banco vazio.'
    );
  }

  const desconhecidas = [...aplicadas].filter((nome) => !arquivos.includes(nome));
  if (desconhecidas.length > 0) {
    throw new Error(
      `O banco registra migrações que não existem nesta pasta: ${desconhecidas.join(', ')}. ` +
        'Confira se está usando a versão certa do repositório.'
    );
  }

  const aplicadasNestaRodada = [];
  for (const arquivo of arquivos) {
    if (aplicadas.has(arquivo)) continue;
    const sql = await fs.readFile(path.join(pasta, arquivo), 'utf8');
    log(`Aplicando ${arquivo} ...`);
    try {
      await cliente.query('begin');
      await cliente.query(sql);
      await cliente.query('commit');
    } catch (erro) {
      await cliente.query('rollback').catch(() => {});
      const linha = linhaDoErro(sql, erro);
      const onde = linha ? ` (perto da linha ${linha})` : '';
      const falha = new Error(
        `A migração ${arquivo} falhou${onde}: ${erro.message}. ` +
          'Nada desta migração foi gravado. Corrija o arquivo e rode de novo.'
      );
      falha.causa = erro;
      throw falha;
    }
    aplicadasNestaRodada.push(arquivo);
  }
  return aplicadasNestaRodada;
}

module.exports = { aplicarPendentes, jaAplicadas, listarArquivos, PASTA_MIGRACOES };
