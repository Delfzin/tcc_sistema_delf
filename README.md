# DELF

Sua academia, em tempo real.

Um sensor preso a cada aparelho da academia avisa se ele está livre, ocupado ou sem sinal. O aluno vê isso no celular e, quando o aparelho que queria está ocupado, recebe a sugestão de outro que trabalha o mesmo músculo. O dono da academia vê a taxa de uso de cada aparelho e os horários de pico.

## Situação deste repositório

Este repositório está sendo montado por fases. Hoje existem:

- **Fase 1, o banco de dados:** pronta e testada. As 29 tabelas, as regras de uso dos aparelhos, os dados de teste e os testes automáticos.
- Fases 2 a 5 (segurança e API, painel do dono, testes da API, fila "é a sua vez"): ainda não feitas.

**Aviso sobre as decisões 1 a 28.** O projeto original (API, site, simulador do sensor e um README com 28 decisões numeradas) está no computador do autor e não estava neste repositório quando a Fase 1 foi feita. Por isso as decisões 1 a 28 não aparecem aqui. A lista deste arquivo continua a numeração a partir da 29. Quando o README original for trazido para cá, as duas listas serão unidas.

## O que a Fase 1 entrega

- Banco PostgreSQL com dois schemas (duas "pastas" dentro do mesmo banco): `core` (pessoas, academias, catálogo, treino, avisos) e `telemetria` (sensores, leituras, sessões de uso, métricas).
- As 29 tabelas do modelo, criadas por 9 arquivos de migração numerados em `supabase/migrations/`.
- A regra completa do sensor: três estados (livre, ocupado, sem sinal), sessão de uso que abre e fecha sozinha, descanso entre séries.
- A tabela de leituras dividida por mês (partição nativa do PostgreSQL).
- Dados de teste em `supabase/seed.sql`, separados das migrações.
- 82 testes automáticos com `node --test`.

## Como rodar no Windows (PowerShell)

O que você precisa ter instalado:

- Node.js 20.12 ou mais novo (testado na versão 22).
- PostgreSQL 15 ou mais novo, instalado no seu computador (testado na versão 16).

Passo a passo. Cada comando está explicado logo abaixo dele.

```powershell
npm install
```
Baixa o único pacote que o projeto usa por enquanto: `pg`, que conversa com o banco. Quando a API for feita na Fase 2, entra também o `express`, o mesmo que o projeto original já usava. Cria a pasta `node_modules`, que não vai para o GitHub.

```powershell
Copy-Item .env.example .env
```
Cria o seu arquivo de configuração. Abra o `.env` e preencha os endereços do banco com a senha do seu PostgreSQL. O `.env` guarda senhas e por isso nunca é enviado ao GitHub.

```powershell
psql -U postgres -c "create database delf"
```
Cria um banco vazio chamado `delf`. As migrações precisam de um banco vazio.

```powershell
npm run migrar
```
Aplica os 9 arquivos de `supabase/migrations/` em ordem. Para ver o que já foi aplicado sem mudar nada: `npm run migrar -- --status`.

```powershell
npm run semear
```
Carrega os dados de TESTE (duas academias de teste, contas, aparelhos, sensores, um treino). Só use em banco de desenvolvimento.

```powershell
npm test
```
Recria um banco `delf_teste` do zero, aplica as migrações e o seed nele e roda todos os testes. Precisa de `DATABASE_URL_TESTE` no `.env`, apontando para o PostgreSQL do seu computador.

Contas de teste (senha de todas: `delf1234`): `carlos@exemplo.com` (aluno), `dono.centro@exemplo.com` (dono), `dono.norte@exemplo.com`, `ana@exemplo.com`, `instrutor.centro@exemplo.com` e `sem.aceite@exemplo.com`.

## Pastas

| Pasta ou arquivo | Para que serve |
|---|---|
| `supabase/migrations/` | Os passos que montam o banco, numerados. Rodam em ordem num banco vazio. |
| `supabase/seed.sql` | Dados de teste. Nunca roda em produção. |
| `scripts/` | Comandos do `npm run`: migrar, semear e preparar o banco de teste. |
| `src/` | Código compartilhado: leitura do `.env`, conexão com o banco, senha. |
| `tests/` | Testes automáticos. |
| `docs/` | Documentos de apoio. O inventário de dados pessoais chega na Fase 2. |
| `REGRAS-DO-SITE.md` | Regras que valem em toda sessão de trabalho no site. |
| `LANCAMENTO.md` | Lista de conferência antes de publicar. |

## As 29 tabelas, em 7 grupos

| Grupo | Tabelas |
|---|---|
| Identidade e acesso | `conta`, `papel`, `permissao`, `papel_permissao`, `conta_papel`, `sessao_login`, `log_auditoria` |
| Pessoas e academia | `academia`, `usuario`, `instrutor`, `matricula`, `checkin` |
| Catálogo | `grupo_muscular`, `tipo_equipamento`, `tipo_equipamento_equivalente`, `exercicio`, `exercicio_grupo_muscular`, `exercicio_tipo_equipamento` |
| Equipamentos e sensores | `equipamento`, `sensor`, `leitura_sensor`, `sessao_uso`, `manutencao_equipamento` |
| Treino | `plano_treino`, `item_treino` |
| Recomendação | `recomendacao` |
| Engajamento e painel | `notificacao`, `integracao_externa`, `metrica_diaria_academia` |

Fora do modelo existe `core.migracao_aplicada`, uma tabela de controle que anota quais migrações já rodaram.

No schema `core` ficam 25 tabelas do modelo. No `telemetria` ficam 4: `sensor`, `leitura_sensor`, `sessao_uso` e `metrica_diaria_academia`.

## Os parâmetros do sensor

Cada academia tem seus próprios valores, na tabela `core.academia`. Para mudar um deles, basta um comando SQL, por exemplo: `update core.academia set segundos_espera_para_livre = 90 where id = 1;`

| Coluna | Valor inicial | O que faz |
|---|---|---|
| `minutos_sem_sinal` | 10 | Sem leitura do sensor há mais que isto, o aparelho aparece como "sem sinal". Vem do manual de decisões. |
| `segundos_espera_para_livre` | 120 | Descanso entre séries: depois do aviso "livre", o aparelho continua "ocupado" por este tempo. Este valor é inicial e NÃO foi calibrado com medição em aparelho real. No manual de decisões, o valor de N ainda está em aberto. |
| `intervalo_batimento_segundos` | 60 | De quanto em quanto tempo o sensor manda o sinal de vida. Precisa caber ao menos 2 vezes dentro de `minutos_sem_sinal`, e o banco recusa uma combinação que não caiba. |
| `duracao_maxima_sessao_minutos` | 180 | Trava de segurança: uma sessão aberta há mais tempo que isto é fechada pela rotina de manutenção (Fase 3). |
| `abertura` e `fechamento` | vazios | Horário de funcionamento. Sem eles, a taxa de uso não pode ser calculada e a API vai devolver vazio com o motivo, nunca um número inventado. |
| `fuso_horario` | America/Sao_Paulo | Usado para fechar o dia nas métricas. |

## Decisões

As decisões 1 a 28 estão no README original, que ainda não foi trazido para este repositório. As seguintes continuam a numeração.

**29. O banco é montado por arquivos numerados, com um executor próprio.**
Cada arquivo de `supabase/migrations/` é um passo pequeno que dá para conferir. Rodam na ordem num banco vazio, colados no editor SQL ou pelo `npm run migrar`. O executor anota na tabela `core.migracao_aplicada` o que já foi feito e nunca repete. Se um arquivo falha, ele é desfeito por inteiro e o programa diz qual arquivo e perto de qual linha. Motivo: não exige Docker nem ferramenta extra, e funciona igual no seu computador e na nuvem.

**30. Dados de teste ficam fora das migrações e têm trava.**
O `supabase/seed.sql` usa nomes de teste ("Academia Teste Centro", "Carlos Teste"). Ele recusa rodar se o banco tiver qualquer academia que não seja de teste, e recusa rodar duas vezes. O comando `npm run semear` também recusa quando `DELF_AMBIENTE=producao`. Motivo: evitar que dado de teste vá parar no banco de verdade e seja confundido com dado real.

**31. O papel de uma pessoa vale para uma academia só.**
A tabela `conta_papel` liga conta, papel e academia. O dono da Academia Teste Centro não tem poder nenhum sobre a Academia Teste Norte. Motivo: o sistema atende várias academias ao mesmo tempo e uma não pode enxergar a outra.

**32. O próprio banco impede misturar academias.**
As tabelas filhas (sensor, sessão de uso, leitura, manutenção) repetem `academia_id` e ligam o par (aparelho, academia) ao aparelho. Assim o banco recusa, por exemplo, um sensor da academia A preso a um aparelho da B, mesmo que o código da API erre. Isto soma ao filtro por academia que toda consulta da API precisa ter. Motivo: duas camadas de proteção para o erro mais grave de um sistema com várias academias.

**33. O sensor não sabe quem está usando o aparelho.**
O campo `usuario_id` da sessão de uso fica vazio e a API do sensor não o preenche. Ligar o uso a uma pessoa só será feito no futuro, com consentimento. Motivo: o acelerômetro não identifica ninguém, e o dado só vira dado pessoal se for cruzado com o login do aluno.

**34. O descanso entre séries é tratado no servidor.**
O sensor manda só "ocupado" ou "livre". Depois do aviso "livre", o aparelho continua "ocupado" por mais N segundos (`segundos_espera_para_livre`). Se o sensor voltar a avisar "ocupado" dentro desse prazo, é a mesma sessão, em vez de abrir outra. Se não voltar, o aparelho vira livre e a sessão já está fechada com a duração certa. Motivo: como o sensor manda só a mudança de estado, o servidor nunca vê o movimento cru e não teria outro jeito de esperar. Deixar N no servidor permite ajustar sem regravar os sensores.

**35. O sinal de vida não vira linha de leitura.**
O sensor manda a mudança de estado e, de tempos em tempos, um sinal de vida repetindo o estado atual. O sinal de vida só atualiza a linha do sensor (`ultimo_sinal_em`). Em `leitura_sensor` entram apenas as mudanças de estado e as voltas de um silêncio. Motivo: um sinal por minuto por sensor encheria a tabela com linhas sem informação nova.

**36. Tempo sem sinal nunca conta como aparelho livre.**
Quando um sensor volta depois de ficar calado, a leitura guarda quando o silêncio começou (`sem_sinal_desde`), e a sessão que estava aberta é fechada no último momento em que o sensor foi ouvido. Assim o tempo calado não é contado como uso e também não será contado como tempo livre. As taxas de uso da Fase 3 dividem o tempo ocupado só pelo tempo em que o sensor estava falando. Motivo: sem isso, um sensor quebrado faria o aparelho parecer "0% de uso", um zero que na verdade é falta de informação.

**37. Os parâmetros ficam em cada academia.**
Ver a tabela de parâmetros acima. Motivo: cada academia tem seu ritmo, e mudar um valor não pode exigir publicar código novo. O banco confere as faixas (por exemplo, o sinal de vida precisa caber duas vezes no prazo de sem sinal).

**38. A divisão por mês de `leitura_sensor` é feita por uma função nossa.**
Usamos a partição nativa do PostgreSQL, sem TimescaleDB e sem `pg_partman`. Uma função SQL de cerca de 30 linhas (`telemetria.garantir_particao_leitura`) cria a partição do mês que falta, e a própria rotina que grava a leitura a chama quando o mês ainda não existe, então uma leitura nunca é perdida por falta de partição. Os meses seguem o calendário de São Paulo. Motivo: funciona igual no seu computador e na nuvem, é testada aqui e o autor consegue explicar cada linha. Se `pg_partman` e `pg_cron` existem no Supabase não foi conferido (ver "O que não foi conferido").

**39. A senha é guardada com scrypt.**
O scrypt já vem dentro do Node, então não é preciso instalar pacote. O resumo guarda junto os parâmetros usados, o que permite endurecê-los no futuro sem invalidar as senhas antigas. O banco recusa gravar uma senha que não esteja nesse formato, para um erro de código não gravar senha em texto puro.

**40. O músculo de um aparelho vem dos exercícios.**
Não existe coluna "músculo" no aparelho. O aparelho trabalha os músculos dos exercícios que se fazem nele (`exercicio_tipo_equipamento` com `exercicio_grupo_muscular`). Motivo: uma única fonte da verdade, sem dois cadastros que podem discordar.

**41. A similaridade entre aparelhos é julgamento editorial.**
A escala de 0 a 100 (outra unidade do mesmo tipo vale 100 e nem precisa de linha na tabela): de 90 a 99, mesmo músculo principal e quase o mesmo movimento; de 70 a 89, mesmo músculo principal com movimento parecido porém diferente; de 50 a 69, mesmo músculo principal com mecânica bem diferente; abaixo de 50, não é cadastrado. Os dois exemplos do manual de decisões foram mantidos (supino reto para supino inclinado, 85; supino reto para crucifixo, 70) e os demais valores foram escritos seguindo a mesma régua. Eles NÃO são medição e precisam ser revisados por um profissional de educação física antes do uso numa academia real. Um teste confere que todo par de aparelhos "parecidos" divide ao menos um músculo principal.

**42. "Em manutenção" não é um quarto estado.**
Os estados continuam sendo três: livre, ocupado e sem sinal. A view `core.vw_estado_equipamento` traz uma coluna à parte, `em_manutencao`, que o site pode usar para avisar. Motivo: manter a decisão dos três estados sem esconder que o aparelho está quebrado.

**43. Os dados de referência vão numa migração e os dados de teste no seed.**
Papéis, permissões, músculos, tipos de aparelho, exercícios e a tabela de similaridade (migração 0009) são necessários em qualquer ambiente, inclusive produção. Academias, contas e sensores de teste ficam só no seed.

**44. Não guardamos o endereço IP de quem entra.**
A tabela de logins ativos só tem o resumo do token, a data de criação e a de validade. Motivo: coletar menos dado pessoal reduz o que precisa ser protegido e explicado na Política de Privacidade. Se um dia a segurança pedir o IP, a decisão é refeita.

## O que não foi conferido

Esta lista é honesta sobre o que ainda não foi verificado:

- **Supabase.** O site do Supabase não pôde ser consultado durante a Fase 1, então nada sobre ele está confirmado: se `pg_partman` e `pg_cron` estão disponíveis, qual endereço de conexão usar, como os papéis `anon` e `authenticated` se comportam. As migrações foram escritas em PostgreSQL comum, sem extensão, para poderem ser coladas no editor SQL do Supabase, mas isso não foi testado lá. As views usam `security_invoker`, que exige PostgreSQL 15 ou mais novo.
- **Windows e PowerShell.** Todos os testes rodaram em Linux. Os comandos foram escritos sem nada específico de Linux, mas não foram rodados no Windows.
- **Versões.** Testado com Node 22 e PostgreSQL 16. Node 20.12 e PostgreSQL 15 e 17 não foram testados.
- **Calibração.** O valor de 120 segundos para o descanso entre séries e os valores de similaridade não foram medidos em aparelhos reais.
- **Volume.** Nenhum teste com milhões de leituras. O comportamento das partições com muito dado não foi medido.
