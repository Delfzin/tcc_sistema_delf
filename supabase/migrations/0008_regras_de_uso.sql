-- DELF, migração 0008: regras de uso dos aparelhos
--
--   telemetria.registrar_leitura(sensor, estado)   o que acontece quando o sensor fala
--   core.vw_estado_equipamento                      estado ao vivo: livre, ocupado ou sem sinal
--   core.vw_tipo_equipamento_grupo_muscular         músculos de cada tipo de aparelho
--
-- Resumo das regras (cada uma está documentada no README):
--   * O sensor manda o estado ("livre" ou "ocupado") quando muda e um sinal de vida
--     periódico repetindo o estado atual. O sinal de vida só atualiza o sensor.
--   * livre -> ocupado abre uma sessão de uso. ocupado -> livre fecha a sessão.
--   * Descanso entre séries: depois do "livre" o aparelho continua "ocupado" por
--     segundos_espera_para_livre (da academia). Se o sensor voltar a avisar
--     "ocupado" nesse prazo, a mesma sessão é retomada, em vez de abrir outra.
--   * Sem sinal há mais de minutos_sem_sinal: o aparelho aparece como "sem sinal".
--     Sem sinal NUNCA vira livre.

-- ---------------------------------------------------------------------------
-- Registrar o que o sensor informou
-- ---------------------------------------------------------------------------
-- Tudo acontece numa única transação: ou grava tudo, ou nada.

create function telemetria.registrar_leitura(p_sensor_id bigint, p_estado text)
returns table (
  estado_registrado text,
  houve_mudanca boolean,
  sessao_id bigint,
  espera_segundos integer,
  batimento_segundos integer
)
language plpgsql
as $$
declare
  v_agora timestamptz;
  v_sensor telemetria.sensor%rowtype;
  v_academia core.academia%rowtype;
  v_limite interval;
  v_espera interval;
  v_silencio_desde timestamptz;
  v_mudou boolean;
  v_ultima telemetria.sessao_uso%rowtype;
  v_sessao_id bigint;
begin
  if p_estado is null or p_estado not in ('livre', 'ocupado') then
    raise exception 'Estado inválido. Use "livre" ou "ocupado".' using errcode = '22023';
  end if;

  -- Trava a linha do sensor até o fim da transação: duas mensagens do mesmo
  -- sensor nunca são processadas ao mesmo tempo.
  select * into v_sensor
    from telemetria.sensor
   where id = p_sensor_id and ativo
     for update;

  if not found then
    raise exception 'Sensor não encontrado ou desativado.' using errcode = 'P0002';
  end if;

  v_agora := clock_timestamp();

  select * into v_academia from core.academia where id = v_sensor.academia_id;
  v_limite := make_interval(mins => v_academia.minutos_sem_sinal);
  v_espera := make_interval(secs => v_academia.segundos_espera_para_livre);

  -- O sensor ficou calado por mais tempo que o limite? Então estava "sem sinal"
  -- e voltou agora. Anotamos quando o silêncio começou.
  if v_sensor.ultimo_sinal_em is not null
     and v_sensor.ultimo_sinal_em + v_limite < v_agora then
    v_silencio_desde := v_sensor.ultimo_sinal_em + v_limite;
  end if;

  v_mudou := v_sensor.ultimo_estado is distinct from p_estado;

  -- Se havia uma sessão aberta antes do silêncio, ela termina no último momento
  -- em que o sensor foi ouvido. O tempo calado não conta como uso. Isto vale
  -- mesmo que a rotina de manutenção ainda não tenha passado por aqui.
  if v_silencio_desde is not null then
    update telemetria.sessao_uso
       set fim_em = greatest(inicio_em, v_sensor.ultimo_sinal_em),
           encerrada_por = 'sem_sinal'
     where equipamento_id = v_sensor.equipamento_id and fim_em is null;
  end if;

  update telemetria.sensor
     set ultimo_sinal_em   = v_agora,
         ultimo_estado     = p_estado,
         ultima_mudanca_em = case when v_mudou then v_agora else ultima_mudanca_em end,
         primeiro_sinal_em = coalesce(primeiro_sinal_em, v_agora)
   where id = v_sensor.id;

  -- Só vira linha de leitura o que tem valor de histórico: mudança de estado
  -- ou volta de um silêncio. O sinal de vida comum não cria linha.
  if v_mudou or v_silencio_desde is not null then
    perform telemetria.garantir_particao_leitura(v_agora);
    insert into telemetria.leitura_sensor
      (sensor_id, academia_id, equipamento_id, recebido_em, estado, mudou_estado, sem_sinal_desde)
    values
      (v_sensor.id, v_sensor.academia_id, v_sensor.equipamento_id, v_agora, p_estado, v_mudou, v_silencio_desde);
  end if;

  if p_estado = 'ocupado' then
    -- Já existe sessão aberta? Então nada a fazer (é só o sinal de vida repetindo).
    select id into v_sessao_id
      from telemetria.sessao_uso
     where equipamento_id = v_sensor.equipamento_id and fim_em is null;

    if v_sessao_id is null then
      select * into v_ultima
        from telemetria.sessao_uso
       where equipamento_id = v_sensor.equipamento_id
       order by inicio_em desc
       limit 1;

      if found
         and v_ultima.encerrada_por = 'sensor'
         and v_ultima.fim_em + v_espera > v_agora then
        -- Descanso entre séries: a pessoa voltou antes de acabar a espera.
        update telemetria.sessao_uso
           set fim_em = null, encerrada_por = null
         where id = v_ultima.id;
        v_sessao_id := v_ultima.id;
      else
        insert into telemetria.sessao_uso (academia_id, equipamento_id, sensor_id, inicio_em)
        values (v_sensor.academia_id, v_sensor.equipamento_id, v_sensor.id, v_agora)
        returning id into v_sessao_id;
      end if;
    end if;
  else
    -- "livre": fecha a sessão aberta, se houver. A duração é calculada pelo banco.
    update telemetria.sessao_uso
       set fim_em = v_agora, encerrada_por = 'sensor'
     where equipamento_id = v_sensor.equipamento_id and fim_em is null
    returning id into v_sessao_id;
  end if;

  return query
    select p_estado,
           v_mudou,
           v_sessao_id,
           v_academia.segundos_espera_para_livre,
           v_academia.intervalo_batimento_segundos;
end;
$$;

comment on function telemetria.registrar_leitura(bigint, text) is
  'Processa uma mensagem do sensor numa única transação: atualiza o sinal de vida, grava a leitura quando o estado muda ou o sensor volta de um silêncio, e abre, fecha ou retoma a sessão de uso. Devolve a configuração que o sensor deve usar.';

-- ---------------------------------------------------------------------------
-- Estado ao vivo de cada aparelho
-- ---------------------------------------------------------------------------
-- "security_invoker" faz a view obedecer às permissões de quem consulta, em vez
-- de às de quem a criou. Exige PostgreSQL 15 ou mais novo.

create view core.vw_estado_equipamento
with (security_invoker = true)
as
select
  x.equipamento_id,
  x.academia_id,
  x.nome,
  x.localizacao,
  x.ativo,
  x.tipo_equipamento_id,
  x.tipo_codigo,
  x.tipo_nome,
  x.categoria,
  x.sensor_id,
  x.ultimo_sinal_em,
  x.estado,
  case x.estado
    when 'ocupado' then x.sessao_inicio_em
    when 'livre' then greatest(
      case when x.sessao_encerrada_por = 'sensor' then x.sessao_fim_em + x.espera end,
      x.ultima_mudanca_em
    )
    else null
  end as desde,
  x.em_manutencao
from (
  select
    e.id as equipamento_id,
    e.academia_id,
    e.nome,
    e.localizacao,
    e.ativo,
    e.tipo_equipamento_id,
    t.codigo as tipo_codigo,
    t.nome as tipo_nome,
    t.categoria,
    s.id as sensor_id,
    s.ultimo_sinal_em,
    s.ultima_mudanca_em,
    u.inicio_em as sessao_inicio_em,
    u.fim_em as sessao_fim_em,
    u.encerrada_por as sessao_encerrada_por,
    make_interval(secs => a.segundos_espera_para_livre) as espera,
    case
      -- Sem sensor, ou sensor que nunca falou: ninguém sabe. Nunca "livre".
      when s.id is null or s.ultimo_sinal_em is null then 'sem_sinal'
      -- Sensor calado há mais que o limite da academia: sem sinal. Nunca "livre".
      when s.ultimo_sinal_em < now() - make_interval(mins => a.minutos_sem_sinal) then 'sem_sinal'
      when u.id is not null and u.fim_em is null then 'ocupado'
      -- Descanso entre séries: o sensor avisou "livre" há pouco, ainda vale "ocupado".
      when u.id is not null
           and u.encerrada_por = 'sensor'
           and u.fim_em + make_interval(secs => a.segundos_espera_para_livre) > now() then 'ocupado'
      else 'livre'
    end as estado,
    exists (
      select 1
        from core.manutencao_equipamento m
       where m.equipamento_id = e.id and m.concluida_em is null
    ) as em_manutencao
  from core.equipamento e
  join core.academia a on a.id = e.academia_id
  join core.tipo_equipamento t on t.id = e.tipo_equipamento_id
  left join telemetria.sensor s on s.equipamento_id = e.id and s.ativo
  left join lateral (
    select su.id, su.inicio_em, su.fim_em, su.encerrada_por
      from telemetria.sessao_uso su
     where su.equipamento_id = e.id
     order by su.inicio_em desc
     limit 1
  ) u on true
) x;

comment on view core.vw_estado_equipamento is
  'Estado ao vivo de cada aparelho: livre, ocupado ou sem_sinal. "sem_sinal" cobre aparelho sem sensor, sensor que nunca falou e sensor calado além do limite da academia; nunca vira livre. "em_manutencao" é informação à parte e não cria um quarto estado.';

-- ---------------------------------------------------------------------------
-- Músculos de cada tipo de aparelho
-- ---------------------------------------------------------------------------
-- Vem dos exercícios que se fazem no aparelho. "principal" é verdadeiro quando
-- algum exercício do aparelho trabalha aquele músculo como músculo principal.

create view core.vw_tipo_equipamento_grupo_muscular
with (security_invoker = true)
as
select
  ete.tipo_equipamento_id,
  egm.grupo_muscular_id,
  bool_or(egm.principal) as principal
from core.exercicio_tipo_equipamento ete
join core.exercicio_grupo_muscular egm on egm.exercicio_id = ete.exercicio_id
group by ete.tipo_equipamento_id, egm.grupo_muscular_id;

insert into core.migracao_aplicada (arquivo) values ('0008_regras_de_uso.sql');
