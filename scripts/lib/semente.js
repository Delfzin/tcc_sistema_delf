'use strict';

// Carrega (e, se pedido, apaga) os dados de TESTE do arquivo supabase/seed.sql.

const fs = require('node:fs/promises');
const path = require('node:path');

const ARQUIVO_SEED = path.join(__dirname, '..', '..', 'supabase', 'seed.sql');

async function aplicarSeed(cliente) {
  const sql = await fs.readFile(ARQUIVO_SEED, 'utf8');
  try {
    await cliente.query('begin');
    await cliente.query(sql);
    await cliente.query('commit');
  } catch (erro) {
    await cliente.query('rollback').catch(() => {});
    throw erro;
  }
}

// Apaga TUDO o que é dado de pessoas, academias e telemetria, mas só se todas
// as academias do banco forem de teste. O catálogo (músculos, aparelhos,
// exercícios, papéis) é mantido.
async function apagarDadosDeTeste(cliente) {
  const { rows } = await cliente.query(
    `select count(*)::int as total from core.academia where nome not like 'Academia Teste%'`
  );
  if (rows[0].total > 0) {
    throw new Error(
      'Recusado: este banco tem academia que não é de teste. Apagar dados de teste só é permitido em banco de teste.'
    );
  }
  await cliente.query('truncate core.conta, core.academia restart identity cascade');
}

module.exports = { aplicarSeed, apagarDadosDeTeste, ARQUIVO_SEED };
