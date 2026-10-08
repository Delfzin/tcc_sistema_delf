-- DELF, DADOS DE TESTE
--
-- ESTE ARQUIVO É SÓ PARA TESTE E DEMONSTRAÇÃO. NUNCA rode em produção.
-- Ele não faz parte das migrações e não deve ser rodado junto com a criação
-- do banco de produção.
--
-- Tudo aqui tem nome de teste de propósito ("Academia Teste Centro", "Carlos Teste"),
-- para ninguém confundir com dado real. Os aparelhos começam SEM SINAL, porque
-- nenhum sensor falou ainda: para vê-los livres ou ocupados, rode o simulador
-- (ele manda as mensagens que o ESP32 mandaria).
--
-- Contas de teste (senha de todas: delf1234):
--   carlos@exemplo.com             aluno da Academia Teste Centro, com treino
--   sem.aceite@exemplo.com         aluno da Centro que ainda não aceitou os termos
--   ana@exemplo.com                aluna da Academia Teste Norte
--   dono.centro@exemplo.com        dono da Academia Teste Centro
--   dono.norte@exemplo.com         dono da Academia Teste Norte
--   instrutor.centro@exemplo.com   instrutor da Academia Teste Centro
--
-- Chaves de teste dos sensores: chave-de-teste-centro-01 até -14 e
-- chave-de-teste-norte-01 até -04 (na ordem dos aparelhos abaixo).
--
-- Versão dos termos aceita nas contas de teste: "rascunho-1". Os textos legais
-- ainda não existem; quando forem publicados, a versão muda e todos aceitam de novo.

-- Trava de segurança. Se este banco tem qualquer academia que não seja de teste,
-- ou se os dados de teste já foram carregados, o arquivo para aqui.
do $$
begin
  if exists (select 1 from core.academia where nome not like 'Academia Teste%') then
    raise exception 'Seed recusado: este banco tem academia que não é de teste. O seed só roda em banco de teste.';
  end if;
  if exists (select 1 from core.academia) then
    raise exception 'Seed recusado: os dados de teste já foram carregados. Para recomeçar num banco de teste, use: npm run semear -- --recomecar';
  end if;
end
$$;

do $$
declare
  c_senha constant text :=
    'scrypt$32768$8$1$NUMu1GnHxfPVxJerf_fGQw$dWiKzDKo08e7PoGVqzwSvUsqwJggMEdIy_l2q8-ILlwQyhFZiLo4DHShTXLCSWH8hy3KJKV6NDvfS4ep_RMOug';
  c_versao constant text := 'rascunho-1';
  v_centro bigint;
  v_norte bigint;
  v_conta bigint;
  v_usuario bigint;
  v_equipamento bigint;
  v_plano bigint;
  p record;
  q record;
  i record;
begin
  -- Academias --------------------------------------------------------------
  insert into core.academia (nome, cidade, uf, abertura, fechamento)
  values ('Academia Teste Centro', 'Cidade de Teste', 'SP', '06:00', '22:00')
  returning id into v_centro;

  insert into core.academia (nome, cidade, uf, abertura, fechamento)
  values ('Academia Teste Norte', 'Cidade de Teste', 'SP', '05:00', '23:00')
  returning id into v_norte;

  -- Pessoas ----------------------------------------------------------------
  for p in
    select * from (values
      ('carlos@exemplo.com', 'Carlos Teste', 'aluno', v_centro, true),
      ('sem.aceite@exemplo.com', 'Aluno Teste Sem Aceite', 'aluno', v_centro, false),
      ('ana@exemplo.com', 'Ana Teste', 'aluno', v_norte, true),
      ('dono.centro@exemplo.com', 'Dono Teste Centro', 'dono', v_centro, true),
      ('dono.norte@exemplo.com', 'Dono Teste Norte', 'dono', v_norte, true),
      ('instrutor.centro@exemplo.com', 'Instrutor Teste Centro', 'instrutor', v_centro, true)
    ) as t (email, nome, papel, academia_id, aceitou)
  loop
    insert into core.conta (
      email, senha_hash,
      termos_versao_aceita, termos_aceitos_em,
      privacidade_versao_aceita, privacidade_aceita_em
    )
    values (
      p.email, c_senha,
      case when p.aceitou then c_versao end, case when p.aceitou then now() end,
      case when p.aceitou then c_versao end, case when p.aceitou then now() end
    )
    returning id into v_conta;

    insert into core.usuario (conta_id, nome) values (v_conta, p.nome)
    returning id into v_usuario;

    insert into core.conta_papel (conta_id, papel_id, academia_id)
    select v_conta, papel.id, p.academia_id from core.papel where papel.codigo = p.papel;

    if p.papel = 'aluno' then
      insert into core.matricula (usuario_id, academia_id) values (v_usuario, p.academia_id);
    elsif p.papel = 'instrutor' then
      insert into core.instrutor (usuario_id, academia_id, especialidade)
      values (v_usuario, p.academia_id, 'Musculação');
    end if;
  end loop;

  -- Aparelhos e sensores ---------------------------------------------------
  for q in
    select * from (values
      (v_centro, 'centro', 1, 'Supino Reto 1', 'supino_reto_maquina', 'Área de peito'),
      (v_centro, 'centro', 2, 'Supino Inclinado 1', 'supino_inclinado_maquina', 'Área de peito'),
      (v_centro, 'centro', 3, 'Crucifixo 1', 'crucifixo_maquina', 'Área de peito'),
      (v_centro, 'centro', 4, 'Puxada Alta 1', 'puxada_alta', 'Área de costas'),
      (v_centro, 'centro', 5, 'Remada Sentada 1', 'remada_sentada_maquina', 'Área de costas'),
      (v_centro, 'centro', 6, 'Tríceps Máquina 1', 'triceps_maquina', 'Área de braços'),
      (v_centro, 'centro', 7, 'Leg Press 45 (1)', 'leg_press_45', 'Área de pernas'),
      (v_centro, 'centro', 8, 'Leg Press 45 (2)', 'leg_press_45', 'Área de pernas'),
      (v_centro, 'centro', 9, 'Hack Squat 1', 'hack_squat', 'Área de pernas'),
      (v_centro, 'centro', 10, 'Cadeira Extensora 1', 'cadeira_extensora', 'Área de pernas'),
      (v_centro, 'centro', 11, 'Mesa Flexora 1', 'mesa_flexora', 'Área de pernas'),
      (v_centro, 'centro', 12, 'Esteira 1', 'esteira', 'Área de cardio'),
      (v_centro, 'centro', 13, 'Esteira 2', 'esteira', 'Área de cardio'),
      (v_centro, 'centro', 14, 'Bicicleta Ergométrica 1', 'bicicleta_ergometrica', 'Área de cardio'),
      (v_norte, 'norte', 1, 'Supino Reto 1', 'supino_reto_maquina', 'Área de peito'),
      (v_norte, 'norte', 2, 'Supino Inclinado 1', 'supino_inclinado_maquina', 'Área de peito'),
      (v_norte, 'norte', 3, 'Leg Press 45 (1)', 'leg_press_45', 'Área de pernas'),
      (v_norte, 'norte', 4, 'Esteira 1', 'esteira', 'Área de cardio')
    ) as t (academia_id, slug, numero, nome, tipo, localizacao)
  loop
    insert into core.equipamento (academia_id, tipo_equipamento_id, nome, localizacao)
    select q.academia_id, te.id, q.nome, q.localizacao
      from core.tipo_equipamento te
     where te.codigo = q.tipo
    returning id into v_equipamento;

    insert into telemetria.sensor (academia_id, equipamento_id, tipo, chave_hash, descricao)
    select q.academia_id,
           v_equipamento,
           case te.categoria when 'cardio' then 'corrente' else 'acelerometro' end,
           sha256(convert_to('chave-de-teste-' || q.slug || '-' || lpad(q.numero::text, 2, '0'), 'UTF8')),
           'Sensor de teste do aparelho ' || q.nome
      from core.tipo_equipamento te
     where te.codigo = q.tipo;
  end loop;

  -- Treinos ----------------------------------------------------------------
  insert into core.plano_treino (usuario_id, academia_id, nome)
  select u.id, v_centro, 'Treino A'
    from core.usuario u join core.conta c on c.id = u.conta_id
   where c.email = 'carlos@exemplo.com'
  returning id into v_plano;

  for i in
    select * from (values
      (1, 'supino_reto_na_maquina', 3, 8, 12),
      (2, 'supino_inclinado_na_maquina', 3, 8, 12),
      (3, 'crucifixo_na_maquina', 3, 12, 15),
      (4, 'triceps_na_maquina', 3, 10, 12)
    ) as t (ordem, exercicio, series, rep_min, rep_max)
  loop
    insert into core.item_treino (plano_treino_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max)
    select v_plano, e.id, i.ordem, i.series, i.rep_min, i.rep_max
      from core.exercicio e
     where e.codigo = i.exercicio;
  end loop;

  -- A Norte não tem cadeira extensora: serve para testar exercício sem aparelho na academia.
  insert into core.plano_treino (usuario_id, academia_id, nome)
  select u.id, v_norte, 'Treino B'
    from core.usuario u join core.conta c on c.id = u.conta_id
   where c.email = 'ana@exemplo.com'
  returning id into v_plano;

  for i in
    select * from (values
      (1, 'leg_press_45', 4, 10, 12),
      (2, 'cadeira_extensora', 3, 12, 15)
    ) as t (ordem, exercicio, series, rep_min, rep_max)
  loop
    insert into core.item_treino (plano_treino_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max)
    select v_plano, e.id, i.ordem, i.series, i.rep_min, i.rep_max
      from core.exercicio e
     where e.codigo = i.exercicio;
  end loop;
end
$$;
