-- DELF, migração 0009: dados de referência
--
-- São dados que o sistema precisa em QUALQUER ambiente, inclusive produção:
-- papéis, permissões, músculos, tipos de aparelho, exercícios e a tabela de
-- similaridade entre aparelhos. Dados de TESTE (academias, contas, sensores)
-- ficam em supabase/seed.sql e nunca entram aqui.
--
-- ATENÇÃO sobre os números de similaridade (0 a 100): são julgamento editorial,
-- não medição. Foram escritos assim, a partir dos dois exemplos do manual de
-- decisões (supino reto -> supino inclinado = 85; supino reto -> crucifixo = 70):
--   90 a 99  mesmo músculo principal e quase o mesmo movimento (muda só a máquina)
--   70 a 89  mesmo músculo principal, movimento parecido porém diferente
--   50 a 69  mesmo músculo principal, mecânica bem diferente
--   abaixo de 50: não cadastrado, porque não serve como alternativa.
-- Antes de usar em academia real, estes valores precisam ser revisados por um
-- profissional de educação física. Para corrigir, basta alterar a linha na lista abaixo.
--
-- Cada par é escrito uma vez e gravado nos dois sentidos.

-- ---------------------------------------------------------------------------
-- Papéis e permissões
-- ---------------------------------------------------------------------------

insert into core.papel (codigo, nome, descricao) values
  ('aluno', 'Aluno', 'Pessoa matriculada que treina na academia.'),
  ('instrutor', 'Instrutor', 'Profissional que acompanha os alunos da academia.'),
  ('dono', 'Dono da academia', 'Responsável pela academia. Vê o painel de uso dos aparelhos.');

insert into core.permissao (codigo, descricao) values
  ('aparelhos.ver', 'Ver o estado ao vivo dos aparelhos da própria academia.'),
  ('treino.proprio', 'Ver o próprio treino e histórico e registrar check-in e check-out.'),
  ('painel.ver', 'Ver o painel de uso dos aparelhos da própria academia.');

insert into core.papel_permissao (papel_id, permissao_id)
select p.id, pm.id
from (values
  ('aluno', 'aparelhos.ver'),
  ('aluno', 'treino.proprio'),
  ('instrutor', 'aparelhos.ver'),
  ('dono', 'aparelhos.ver'),
  ('dono', 'painel.ver')
) as v (papel, permissao)
join core.papel p on p.codigo = v.papel
join core.permissao pm on pm.codigo = v.permissao;

-- ---------------------------------------------------------------------------
-- Grupos musculares
-- ---------------------------------------------------------------------------

insert into core.grupo_muscular (codigo, nome) values
  ('peito', 'Peito'),
  ('costas', 'Costas'),
  ('ombros', 'Ombros'),
  ('trapezio', 'Trapézio'),
  ('biceps', 'Bíceps'),
  ('triceps', 'Tríceps'),
  ('antebraco', 'Antebraço'),
  ('abdomen', 'Abdômen'),
  ('lombar', 'Lombar'),
  ('quadriceps', 'Quadríceps'),
  ('posterior_coxa', 'Posterior de coxa'),
  ('gluteos', 'Glúteos'),
  ('adutores', 'Adutores'),
  ('panturrilha', 'Panturrilha'),
  ('cardio', 'Cardiovascular');

-- ---------------------------------------------------------------------------
-- Tipos de aparelho
-- ---------------------------------------------------------------------------

insert into core.tipo_equipamento (codigo, nome, categoria) values
  ('supino_reto_maquina', 'Supino reto (máquina)', 'musculacao'),
  ('supino_inclinado_maquina', 'Supino inclinado (máquina)', 'musculacao'),
  ('crucifixo_maquina', 'Crucifixo (máquina)', 'musculacao'),
  ('crossover_polia', 'Crossover (polia dupla)', 'musculacao'),
  ('puxada_alta', 'Puxada alta', 'musculacao'),
  ('barra_fixa_assistida', 'Barra fixa assistida', 'musculacao'),
  ('remada_sentada_maquina', 'Remada sentada (máquina)', 'musculacao'),
  ('remada_baixa_polia', 'Remada baixa (polia)', 'musculacao'),
  ('desenvolvimento_maquina', 'Desenvolvimento (máquina)', 'musculacao'),
  ('elevacao_lateral_maquina', 'Elevação lateral (máquina)', 'musculacao'),
  ('rosca_biceps_maquina', 'Rosca bíceps (máquina)', 'musculacao'),
  ('triceps_maquina', 'Tríceps (máquina)', 'musculacao'),
  ('polia_ajustavel', 'Polia ajustável', 'musculacao'),
  ('smith', 'Smith (barra guiada)', 'musculacao'),
  ('leg_press_45', 'Leg press 45 graus', 'musculacao'),
  ('leg_press_horizontal', 'Leg press horizontal', 'musculacao'),
  ('hack_squat', 'Hack squat', 'musculacao'),
  ('cadeira_extensora', 'Cadeira extensora', 'musculacao'),
  ('mesa_flexora', 'Mesa flexora', 'musculacao'),
  ('cadeira_flexora', 'Cadeira flexora', 'musculacao'),
  ('cadeira_adutora', 'Cadeira adutora', 'musculacao'),
  ('cadeira_abdutora', 'Cadeira abdutora', 'musculacao'),
  ('gluteo_maquina', 'Glúteo (máquina)', 'musculacao'),
  ('panturrilha_sentada', 'Panturrilha sentada', 'musculacao'),
  ('panturrilha_em_pe', 'Panturrilha em pé', 'musculacao'),
  ('abdominal_maquina', 'Abdominal (máquina)', 'musculacao'),
  ('extensao_lombar', 'Extensão lombar', 'musculacao'),
  ('esteira', 'Esteira', 'cardio'),
  ('bicicleta_ergometrica', 'Bicicleta ergométrica', 'cardio'),
  ('eliptico', 'Elíptico', 'cardio'),
  ('simulador_de_escada', 'Simulador de escada', 'cardio');

-- ---------------------------------------------------------------------------
-- Exercícios, com os músculos que trabalham e os aparelhos em que são feitos
-- ---------------------------------------------------------------------------

insert into core.exercicio (codigo, nome) values
  ('supino_reto_na_maquina', 'Supino reto na máquina'),
  ('supino_inclinado_na_maquina', 'Supino inclinado na máquina'),
  ('crucifixo_na_maquina', 'Crucifixo na máquina'),
  ('crossover_na_polia', 'Crossover na polia'),
  ('supino_reto_no_smith', 'Supino reto no Smith'),
  ('puxada_alta', 'Puxada alta'),
  ('barra_fixa_assistida', 'Barra fixa assistida'),
  ('remada_sentada_na_maquina', 'Remada sentada na máquina'),
  ('remada_baixa_na_polia', 'Remada baixa na polia'),
  ('desenvolvimento_na_maquina', 'Desenvolvimento na máquina'),
  ('desenvolvimento_no_smith', 'Desenvolvimento no Smith'),
  ('elevacao_lateral_na_maquina', 'Elevação lateral na máquina'),
  ('rosca_biceps_na_maquina', 'Rosca bíceps na máquina'),
  ('rosca_biceps_na_polia', 'Rosca bíceps na polia'),
  ('triceps_na_maquina', 'Tríceps na máquina'),
  ('triceps_na_polia', 'Tríceps na polia'),
  ('leg_press_45', 'Leg press 45 graus'),
  ('leg_press_horizontal', 'Leg press horizontal'),
  ('agachamento_no_hack', 'Agachamento no hack'),
  ('agachamento_no_smith', 'Agachamento no Smith'),
  ('cadeira_extensora', 'Cadeira extensora'),
  ('mesa_flexora', 'Mesa flexora'),
  ('cadeira_flexora', 'Cadeira flexora'),
  ('cadeira_adutora', 'Cadeira adutora'),
  ('cadeira_abdutora', 'Cadeira abdutora'),
  ('gluteo_na_maquina', 'Glúteo na máquina'),
  ('panturrilha_sentado', 'Panturrilha sentado'),
  ('panturrilha_em_pe', 'Panturrilha em pé'),
  ('abdominal_na_maquina', 'Abdominal na máquina'),
  ('extensao_lombar', 'Extensão lombar'),
  ('encolhimento_no_smith', 'Encolhimento no Smith'),
  ('corrida_na_esteira', 'Caminhada ou corrida na esteira'),
  ('bicicleta_ergometrica', 'Bicicleta ergométrica'),
  ('eliptico', 'Elíptico'),
  ('simulador_de_escada', 'Simulador de escada');

-- Cada linha: exercício, músculo, e se é o músculo principal (true) ou auxiliar (false).
-- Se um código estiver escrito errado, a migração para com uma mensagem clara
-- em vez de pular a linha em silêncio.
do $$
declare
  v record;
begin
  for v in
    select * from (values
      ('supino_reto_na_maquina', 'peito', true),
      ('supino_reto_na_maquina', 'ombros', false),
      ('supino_reto_na_maquina', 'triceps', false),
      ('supino_inclinado_na_maquina', 'peito', true),
      ('supino_inclinado_na_maquina', 'ombros', false),
      ('supino_inclinado_na_maquina', 'triceps', false),
      ('crucifixo_na_maquina', 'peito', true),
      ('crucifixo_na_maquina', 'ombros', false),
      ('crossover_na_polia', 'peito', true),
      ('supino_reto_no_smith', 'peito', true),
      ('supino_reto_no_smith', 'ombros', false),
      ('supino_reto_no_smith', 'triceps', false),
      ('puxada_alta', 'costas', true),
      ('puxada_alta', 'biceps', false),
      ('barra_fixa_assistida', 'costas', true),
      ('barra_fixa_assistida', 'biceps', false),
      ('remada_sentada_na_maquina', 'costas', true),
      ('remada_sentada_na_maquina', 'biceps', false),
      ('remada_sentada_na_maquina', 'trapezio', false),
      ('remada_baixa_na_polia', 'costas', true),
      ('remada_baixa_na_polia', 'biceps', false),
      ('desenvolvimento_na_maquina', 'ombros', true),
      ('desenvolvimento_na_maquina', 'triceps', false),
      ('desenvolvimento_no_smith', 'ombros', true),
      ('desenvolvimento_no_smith', 'triceps', false),
      ('elevacao_lateral_na_maquina', 'ombros', true),
      ('rosca_biceps_na_maquina', 'biceps', true),
      ('rosca_biceps_na_maquina', 'antebraco', false),
      ('rosca_biceps_na_polia', 'biceps', true),
      ('rosca_biceps_na_polia', 'antebraco', false),
      ('triceps_na_maquina', 'triceps', true),
      ('triceps_na_polia', 'triceps', true),
      ('leg_press_45', 'quadriceps', true),
      ('leg_press_45', 'gluteos', false),
      ('leg_press_45', 'posterior_coxa', false),
      ('leg_press_horizontal', 'quadriceps', true),
      ('leg_press_horizontal', 'gluteos', false),
      ('leg_press_horizontal', 'posterior_coxa', false),
      ('agachamento_no_hack', 'quadriceps', true),
      ('agachamento_no_hack', 'gluteos', false),
      ('agachamento_no_smith', 'quadriceps', true),
      ('agachamento_no_smith', 'gluteos', false),
      ('agachamento_no_smith', 'posterior_coxa', false),
      ('cadeira_extensora', 'quadriceps', true),
      ('mesa_flexora', 'posterior_coxa', true),
      ('cadeira_flexora', 'posterior_coxa', true),
      ('cadeira_adutora', 'adutores', true),
      ('cadeira_abdutora', 'gluteos', true),
      ('gluteo_na_maquina', 'gluteos', true),
      ('gluteo_na_maquina', 'posterior_coxa', false),
      ('panturrilha_sentado', 'panturrilha', true),
      ('panturrilha_em_pe', 'panturrilha', true),
      ('abdominal_na_maquina', 'abdomen', true),
      ('extensao_lombar', 'lombar', true),
      ('extensao_lombar', 'gluteos', false),
      ('extensao_lombar', 'posterior_coxa', false),
      ('encolhimento_no_smith', 'trapezio', true),
      ('encolhimento_no_smith', 'ombros', false),
      ('corrida_na_esteira', 'cardio', true),
      ('corrida_na_esteira', 'panturrilha', false),
      ('bicicleta_ergometrica', 'cardio', true),
      ('bicicleta_ergometrica', 'quadriceps', false),
      ('eliptico', 'cardio', true),
      ('simulador_de_escada', 'cardio', true),
      ('simulador_de_escada', 'gluteos', false),
      ('simulador_de_escada', 'quadriceps', false)
    ) as t (exercicio, grupo, principal)
  loop
    insert into core.exercicio_grupo_muscular (exercicio_id, grupo_muscular_id, principal)
    select e.id, g.id, v.principal
      from core.exercicio e, core.grupo_muscular g
     where e.codigo = v.exercicio and g.codigo = v.grupo;
    if not found then
      raise exception 'Código inexistente em exercício/músculo: % / %', v.exercicio, v.grupo;
    end if;
  end loop;
end
$$;

do $$
declare
  v record;
begin
  for v in
    select * from (values
      ('supino_reto_na_maquina', 'supino_reto_maquina'),
      ('supino_inclinado_na_maquina', 'supino_inclinado_maquina'),
      ('crucifixo_na_maquina', 'crucifixo_maquina'),
      ('crossover_na_polia', 'crossover_polia'),
      ('supino_reto_no_smith', 'smith'),
      ('puxada_alta', 'puxada_alta'),
      ('barra_fixa_assistida', 'barra_fixa_assistida'),
      ('remada_sentada_na_maquina', 'remada_sentada_maquina'),
      ('remada_baixa_na_polia', 'remada_baixa_polia'),
      ('desenvolvimento_na_maquina', 'desenvolvimento_maquina'),
      ('desenvolvimento_no_smith', 'smith'),
      ('elevacao_lateral_na_maquina', 'elevacao_lateral_maquina'),
      ('rosca_biceps_na_maquina', 'rosca_biceps_maquina'),
      ('rosca_biceps_na_polia', 'polia_ajustavel'),
      ('triceps_na_maquina', 'triceps_maquina'),
      ('triceps_na_polia', 'polia_ajustavel'),
      ('leg_press_45', 'leg_press_45'),
      ('leg_press_horizontal', 'leg_press_horizontal'),
      ('agachamento_no_hack', 'hack_squat'),
      ('agachamento_no_smith', 'smith'),
      ('cadeira_extensora', 'cadeira_extensora'),
      ('mesa_flexora', 'mesa_flexora'),
      ('cadeira_flexora', 'cadeira_flexora'),
      ('cadeira_adutora', 'cadeira_adutora'),
      ('cadeira_abdutora', 'cadeira_abdutora'),
      ('gluteo_na_maquina', 'gluteo_maquina'),
      ('panturrilha_sentado', 'panturrilha_sentada'),
      ('panturrilha_em_pe', 'panturrilha_em_pe'),
      ('abdominal_na_maquina', 'abdominal_maquina'),
      ('extensao_lombar', 'extensao_lombar'),
      ('encolhimento_no_smith', 'smith'),
      ('corrida_na_esteira', 'esteira'),
      ('bicicleta_ergometrica', 'bicicleta_ergometrica'),
      ('eliptico', 'eliptico'),
      ('simulador_de_escada', 'simulador_de_escada')
    ) as t (exercicio, tipo)
  loop
    insert into core.exercicio_tipo_equipamento (exercicio_id, tipo_equipamento_id)
    select e.id, t.id
      from core.exercicio e, core.tipo_equipamento t
     where e.codigo = v.exercicio and t.codigo = v.tipo;
    if not found then
      raise exception 'Código inexistente em exercício/aparelho: % / %', v.exercicio, v.tipo;
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Similaridade entre tipos de aparelho (julgamento editorial, ver aviso no topo)
-- ---------------------------------------------------------------------------

do $$
declare
  v record;
begin
  for v in
    select * from (values
      -- Peito
      ('supino_reto_maquina', 'supino_inclinado_maquina', 85),
      ('supino_reto_maquina', 'crucifixo_maquina', 70),
      ('supino_inclinado_maquina', 'crucifixo_maquina', 70),
      ('supino_reto_maquina', 'crossover_polia', 65),
      ('supino_inclinado_maquina', 'crossover_polia', 60),
      ('crucifixo_maquina', 'crossover_polia', 80),
      ('supino_reto_maquina', 'smith', 65),
      -- Costas
      ('puxada_alta', 'barra_fixa_assistida', 85),
      ('puxada_alta', 'remada_sentada_maquina', 70),
      ('puxada_alta', 'remada_baixa_polia', 65),
      ('remada_sentada_maquina', 'remada_baixa_polia', 90),
      ('barra_fixa_assistida', 'remada_sentada_maquina', 60),
      ('barra_fixa_assistida', 'remada_baixa_polia', 60),
      -- Ombros
      ('desenvolvimento_maquina', 'elevacao_lateral_maquina', 60),
      ('desenvolvimento_maquina', 'smith', 65),
      -- Braços
      ('rosca_biceps_maquina', 'polia_ajustavel', 75),
      ('triceps_maquina', 'polia_ajustavel', 75),
      -- Pernas
      ('leg_press_45', 'leg_press_horizontal', 95),
      ('leg_press_45', 'hack_squat', 85),
      ('leg_press_horizontal', 'hack_squat', 80),
      ('leg_press_45', 'cadeira_extensora', 60),
      ('leg_press_horizontal', 'cadeira_extensora', 60),
      ('hack_squat', 'cadeira_extensora', 60),
      ('hack_squat', 'smith', 75),
      ('leg_press_45', 'smith', 65),
      ('mesa_flexora', 'cadeira_flexora', 90),
      ('cadeira_abdutora', 'gluteo_maquina', 65),
      ('panturrilha_sentada', 'panturrilha_em_pe', 85),
      -- Cardio
      ('esteira', 'eliptico', 80),
      ('esteira', 'bicicleta_ergometrica', 70),
      ('esteira', 'simulador_de_escada', 75),
      ('eliptico', 'bicicleta_ergometrica', 75),
      ('eliptico', 'simulador_de_escada', 75),
      ('bicicleta_ergometrica', 'simulador_de_escada', 65)
    ) as t (tipo_a, tipo_b, similaridade)
  loop
    insert into core.tipo_equipamento_equivalente (tipo_equipamento_id, equivalente_id, similaridade)
    select a.id, b.id, v.similaridade
      from core.tipo_equipamento a, core.tipo_equipamento b
     where a.codigo = v.tipo_a and b.codigo = v.tipo_b
    union all
    select b.id, a.id, v.similaridade
      from core.tipo_equipamento a, core.tipo_equipamento b
     where a.codigo = v.tipo_a and b.codigo = v.tipo_b;
    if not found then
      raise exception 'Código inexistente na similaridade: % / %', v.tipo_a, v.tipo_b;
    end if;
  end loop;
end
$$;

insert into core.migracao_aplicada (arquivo) values ('0009_dados_de_referencia.sql');
