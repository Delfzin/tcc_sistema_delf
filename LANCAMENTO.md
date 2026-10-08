# Lista de conferência para publicar

Marque cada item só depois de conferir de verdade. Nada de publicar com item em aberto. Todos os itens começam desmarcados.

## Site

- [ ] Domínio próprio ligado e funcionando com HTTPS.
- [ ] Ícone da aba (favicon) colocado.
- [ ] Nenhum selo "Feito com IA" em lugar nenhum do site.
- [ ] Página de Política de Privacidade no ar, com texto revisado por quem entende de LGPD.
- [ ] Página de Termos de Uso no ar, com texto revisado.
- [ ] Os links da Política e dos Termos aparecem no cadastro e no rodapé.
- [ ] Revisão das regras de `REGRAS-DO-SITE.md`: sem degradê roxo, sem botão em pílula, sem emoji, sem travessão, sem animação exagerada.
- [ ] Nenhum número, avaliação ou contador de cliente escrito à mão no site. Todo número vem da API.
- [ ] O endereço da API no site aponta para a API publicada, não para `localhost`.

## API e banco

- [ ] Variáveis de ambiente configuradas no servidor de publicação (nenhuma senha dentro do código nem do GitHub). Ver `.env.example`.
- [ ] `DELF_AMBIENTE=producao` definido no servidor.
- [ ] Endereço do site (o domínio próprio) liberado no CORS, e nenhum outro endereço além dele.
- [ ] Chaves e senhas de teste trocadas: senha do banco, chave de cada sensor, qualquer segredo usado no desenvolvimento.
- [ ] Seed (`supabase/seed.sql`) NÃO foi rodado no banco de produção. Conferir que não existe "Academia Teste" nem "carlos@exemplo.com" lá.
- [ ] Migrações aplicadas em ordem no banco de produção (`npm run migrar -- --status` não mostra nenhuma pendente).
- [ ] Conexão com o banco criptografada e verificada (`DATABASE_SSL=ligado`).
- [ ] A API é a única porta de entrada dos dados: as chaves públicas do provedor do banco não conseguem ler nem escrever em `core` nem em `telemetria`. Rodar o teste de bloqueio contra o banco de produção.
- [ ] A versão dos Termos de Uso e da Política de Privacidade deixou de ser "rascunho-1" e passou a ser a versão do texto publicado.
- [ ] Rotina de manutenção (fechar sessões abertas há tempo demais, calcular a métrica do dia, criar a partição do próximo mês) agendada e conferida.
- [ ] Backup do banco ligado, e uma restauração testada pelo menos uma vez.
- [ ] Prazo de guarda de cada dado pessoal decidido e conferido com `docs/INVENTARIO-DE-DADOS.md`.

## Sensores

- [ ] Cada sensor tem a própria chave, diferente das chaves de teste.
- [ ] Valor da espera antes de virar "livre" (descanso entre séries) calibrado com medição em aparelho real, e não mais o valor inicial de 120 segundos.
- [ ] Ponto de Wi-Fi dedicado aos sensores na academia.
- [ ] Tomadas e instalação elétrica dos sensores conferidas.

## Repositório

- [ ] Decidido se o repositório fica público ou privado.
- [ ] Nenhum arquivo `.env` nem senha dentro do histórico do GitHub.
