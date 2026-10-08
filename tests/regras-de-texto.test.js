'use strict';

// Regra de escrita do projeto: nenhum emoji e nenhum travessão em documentos,
// migrações, seed e código. Evita o texto com cara de gerado no automático.
//
// Os caracteres proibidos são montados aqui a partir do número deles
// (String.fromCharCode), para este próprio arquivo não ser reprovado por eles.

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');

const RAIZ = path.join(__dirname, '..');
const PASTAS_IGNORADAS = new Set(['node_modules', '.git', 'coverage']);
const EXTENSOES = new Set(['.md', '.sql', '.js', '.json', '.html', '.css', '.example']);

const TRAVESSAO = String.fromCharCode(0x2014);
const TRACO_MEDIO = String.fromCharCode(0x2013);

const PROIBIDOS = [
  { nome: 'travessão', regex: new RegExp(TRAVESSAO, 'u') },
  { nome: 'traço médio', regex: new RegExp(TRACO_MEDIO, 'u') },
  { nome: 'emoji', regex: /[\p{Extended_Pictographic}\p{Emoji_Presentation}\u{1F1E6}-\u{1F1FF}]/u },
];

async function listar(pasta) {
  const encontrados = [];
  for (const entrada of await fs.readdir(pasta, { withFileTypes: true })) {
    if (PASTAS_IGNORADAS.has(entrada.name)) continue;
    const caminho = path.join(pasta, entrada.name);
    if (entrada.isDirectory()) {
      encontrados.push(...(await listar(caminho)));
    } else if (EXTENSOES.has(path.extname(entrada.name)) || entrada.name === '.env.example') {
      encontrados.push(caminho);
    }
  }
  return encontrados;
}

describe('regra de escrita: sem emoji e sem travessão', () => {
  it('nenhum arquivo do projeto contém emoji, travessão ou traço médio', async () => {
    const arquivos = await listar(RAIZ);
    assert.ok(arquivos.length > 10, 'a varredura deveria encontrar os arquivos do projeto');

    const problemas = [];
    for (const arquivo of arquivos) {
      if (arquivo.endsWith('package-lock.json')) continue;
      const linhas = (await fs.readFile(arquivo, 'utf8')).split('\n');
      linhas.forEach((linha, indice) => {
        for (const proibido of PROIBIDOS) {
          if (proibido.regex.test(linha)) {
            problemas.push(`${path.relative(RAIZ, arquivo)}:${indice + 1} tem ${proibido.nome}`);
          }
        }
      });
    }
    assert.deepEqual(problemas, []);
  });

  it('o detector funciona: reconhece os caracteres proibidos', () => {
    assert.ok(PROIBIDOS[0].regex.test(`texto ${TRAVESSAO} com travessão`));
    assert.ok(PROIBIDOS[1].regex.test(`1${TRACO_MEDIO}2`));
    assert.ok(PROIBIDOS[2].regex.test('ok \u{1F600}'));
    assert.ok(!PROIBIDOS[2].regex.test('ação, coração, não, é, ü'));
    assert.ok(!PROIBIDOS[0].regex.test('traço-simples e -- do SQL'));
  });
});
