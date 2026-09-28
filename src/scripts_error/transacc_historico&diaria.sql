
# ------ file:TRANSACCIONES HISTORICAS + DIARIAS ------------------
-- SELECT @w_operacionca:=147900,  @div_ini:=41,  @div_hasta:=91; @concepto:='FECI' | 'CAP' | 'INT'

SELECT @w_banco := op_banco as banco, @w_operacionca:= op_operacion as op, op.op_cliente,op.op_nombre, op.op_migrada, op_reestructuracion,op_estado,
op_monto, @w_fecha_mov:=op_fecha_ult_proceso as op_fecha_ult_proceso, op_fecha_ini, op_fecha_fin, op_estado, op_tipo_amortizacion, op.op_toperacion, op.*
FROM cob_cartera.ca_operacion op WHERE
op_operacion = @w_operacionca
;

# transaccion vs amortizacion (historica + diaria)
select
concat(case when amh_cuota < abs(amh_gracia ) and amh_gracia < 0 then 'G-' else '' end,
case when amh_pagado < 0 then 'P-' else '' end) as 'G(-)>Cuota',
amh_acumulado + amh_gracia-amh_pagado as 'sld_acum',
case when amh_estado = 3 THEN case when amh_acumulado + amh_gracia - amh_pagado = 0 then '' else 'NOK' end
when amh_estado = 2 THEN case when amh_acumulado <> amh_cuota or amh_pagado > amh_acumulado or amh_pagado > amh_cuota then 'NOK2' else '' end
else '' end as 'ErrorCAN',
date(tr.tr_fecha_ref) as 'tr_fecha_ref', date(tr_fecha_mov) as 'tr_fecha_mov',
am.amh_secuencial, tr.tr_tran, tr.tr_estado,
(select ab_tipo_reduccion||'.'||ab_tipo_cobro||'.'||ab_tipo_aplicacion||'.'||ifnull(ab_extraordinario,'') ||'.'||
ifnull((select max('Con') from cob_cartera.ca_abono_det abd where abd_operacion = ab.ab_operacion and abd_secuencial_ing = ab.ab_secuencial_ing and abd.abd_tipo = 'CON' ) ,'Pag')
||'.'|| case when ab.ab_solo_cap = 'S' then 'K' else 'N' end
from cob_cartera.ca_abono ab
where ab_operacion = tr.tr_operacion and ab_estado not in ('RV', 'E')
and ab_secuencial_pag = tr.tr_secuencial and tr.tr_tran = 'PAG') as 'TipoPAG',
am.amh_dividendo , dih_estado,
amh_concepto, amh_estado, amh_secuencia , amh_cuota, amh_gracia, amh_pagado, amh_acumulado, am.amh_acumulado_ade , am.amh_periodo ,
date(dih_fecha_ini) as 'dih_fecha_ini', date(dih_fecha_ven) as 'dih_fecha_ven', di.dih_dias_cuota ,
(amh_cuota+amh_gracia) as 'cuota_AM', oph_cuota as 'cuota_OP', oph_tipo_amortizacion, dih_de_capital, dih_de_interes, oph_operacion, oph_banco, op.oph_cuota_ballom , oph_estado, oph_toperacion, op.oph_fecha_ult_proceso 
from cob_cartera.ca_amortizacion_his am, cob_cartera.ca_transaccion tr , cob_cartera.ca_dividendo_his di , cob_cartera.ca_operacion_his op
where am.amh_operacion = @w_operacionca
and amh_operacion = dih_operacion
and amh_dividendo = dih_dividendo
and amh_secuencial = dih_secuencial
and amh_operacion = tr_operacion
and amh_secuencial = tr_secuencial
and amh_operacion = oph_operacion
and amh_secuencial = oph_secuencial
and tr_estado != 'RV'
and amh_dividendo between @div_ini and @div_hasta   
and amh_concepto in (@concepto)
and amh_secuencial between 1 and 999999
UNION
select
concat(case when am_cuota < abs(am_gracia ) and am_gracia < 0 then 'G-' else '' end,
case when am_pagado < 0 then 'P-' else '' end) as 'G(-)>Cuota',
am_acumulado +am_gracia-am_pagado as 'sld_acum',
case when am_estado = 3 THEN case when am_acumulado + am_gracia - am_pagado = 0 then '' else 'NOK' end
when am_estado = 2 THEN case when am_acumulado <> am_cuota or am_pagado > am_acumulado or am_pagado > am_cuota then 'NOK2' else '' end
else '' end as 'ErrorCAN',
date(op_fecha_ult_proceso) as tr_fecha_ref, 'Hoy' as tr_fecha_mov,
99999 AS secuencial, 'Hoy' as tr_tran, 'Hoy' as tr_estado,
'' as 'TipoPAG',
am.am_dividendo , di_estado,
am_concepto, am_estado, am_secuencia , am_cuota, am_gracia, am_pagado, am_acumulado, am.am_acumulado_ade , am.am_periodo,
date(di_fecha_ini) as di_fecha_ini, date(di_fecha_ven) as di_Fecha_ven, di_dias_cuota,
(am_cuota+am_gracia) as 'cuota_AM', op_cuota, op_tipo_amortizacion, di_de_capital, di_de_interes, op_operacion, op_banco, op.op_cuota_ballom , op_estado, op_toperacion, op.op_fecha_ult_proceso
from cob_cartera.ca_amortizacion am, cob_cartera.ca_dividendo di , cob_cartera.ca_operacion op
where am.am_operacion = @w_operacionca
and am_operacion = di_operacion
and am_dividendo = di_dividendo
and am_operacion = op_operacion
and am_dividendo between @div_ini and @div_hasta      
and am_concepto in (@concepto)
;