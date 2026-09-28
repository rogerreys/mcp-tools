# ------ file:TRANSACCIONES DIARIAS ------------------
SELECT op.op_cliente,op.op_nombre, @w_banco := op_banco as banco, @operacion:= op_operacion as op, op.op_migrada, op_reestructuracion,op_estado,
op_monto, @w_fecha_mov:=op_fecha_ult_proceso as op_fecha_ult_proceso, op_fecha_ini, op_fecha_fin, op_estado, op_tipo_amortizacion, op.op_toperacion, op.*
FROM cob_cartera.ca_operacion op WHERE
op_operacion = @operacion
;
-- ErrorCAN -> Deteccion de errores em INTERES
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
where am.am_operacion = @operacion
and am_operacion = di_operacion
and am_dividendo = di_dividendo
and am_operacion = op_operacion
and am_concepto in ('INT')
HAVING ErrorCAN like "NOK%"
;

-- ErrorCAN -> Deteccion de errores em FECI
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
where am.am_operacion = @operacion
and am_operacion = di_operacion
and am_dividendo = di_dividendo
and am_operacion = op_operacion
and am_concepto in ('FECI')
HAVING ErrorCAN like "NOK%"
;

-- ErrorCAN -> Deteccion de errores em CAP
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
where am.am_operacion = @operacion
and am_operacion = di_operacion
and am_dividendo = di_dividendo
and am_operacion = op_operacion
and am_concepto in ('CAP') 
HAVING ErrorCAN like "NOK%"
;