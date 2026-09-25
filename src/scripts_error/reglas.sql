# --------- file:REGLAS DE ERROR ------------------
# SELECT @w_banco:='0000579599';
SELECT @w_operacionca:=147900;

SELECT @w_banco := op_banco as banco, @w_operacionca:= op_operacion as op, 
op_monto, op_fecha_ult_proceso, op_fecha_ini, op_fecha_fin, op_estado, op_tipo_amortizacion, op.* 
FROM cob_cartera.ca_operacion op WHERE 
op_operacion = @w_operacionca
#op_banco IN (@w_banco)
;

-- VAL-01 OPERACIONES CON FECI CERO QUE TUVIERON REAJUSTE
-- CUOTA = 0 Y GRACIA NEGATIVA Y UNA TRANSACCION MANUAL POSTERIOR AL REAJUSTE
select 
	'R01: OPERACIONES CON FECI CERO QUE TUVIERON REAJUSTE' as 'Regla-01',
	banco, operacion,  op_estado, op_tipo_amortizacion, op_toperacion , origen,
	fecha_ref, secuencial, dividendo, concepto , 
	(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
	am_dividendo, am_estado, am_concepto , am_cuota, am_gracia, am_pagado, am_acumulado ,am_secuencia,
	(select op_estado from cob_cartera.ca_operacion where op_operacion = rej.operacion) as 'Op_estado',
	case when am_gracia < 0 then 	case when am_acumulado < am_pagado then 1 else 0 end 
	else case when am_acumulado + am_gracia < am_pagado then 1 else 0 end end           as 'Error1',
	case when am_acumulado + am_gracia < am_pagado then 1 else 0 end                    as 'Error2',
	(select max(tr_tran) from cob_cartera.ca_transaccion t2 where tr_operacion = rej.operacion and tr_secuencial > rej.secuencial 
	 and tr_estado <> 'RV'
	 and tr_tran  IN('DES', 'RES', 'ETM','PRO', 'AJP', 'MPC',  'SUM', 'ACE',  'MAN', 'VTA','AIO',
	                 'ISG','ESG','CDP','ESD','CTC','DMR','ELS','CDF','ALI', 'ARG','CPE','EBE') )  as 'Trn_MAN'
from cob_cartera.ca_amortizacion am,
(
	select 
		tr_operacion      as operacion,      tr_secuencial as secuencial, 
		tr_secuencial_ref as secuencial_ref, dtr_concepto  as concepto, 
		dtr_dividendo     as dividendo,      tr_fecha_ref  as fecha_ref,
		tr_fecha_mov      as fecha_mov,      (select min(tr_secuencial) from cob_cartera.ca_transaccion, cob_cartera.ca_operacion_his
															where tr_operacion = oph_operacion and tr_secuencial = oph_secuencial
															and tr_operacion = t1.tr_operacion 
															and tr_estado <> 'RV'
															and tr_secuencial > t1.tr_secuencial) as siguiente,
		tr_banco          as banco,
		op_tipo_amortizacion, op_toperacion , op_estado, case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen'
	from 	cob_cartera.ca_transaccion t1, cob_cartera.ca_det_trn dtr,
			cob_cartera.ca_reajuste r, cob_cartera.ca_reajuste_det rd,
			cob_cartera.ca_operacion o
	where re_operacion = tr_operacion
	and re_secuencial = tr_secuencial_ref
	and re_operacion = red_operacion
	and re_secuencial = red_secuencial
	and red_porcentaje = 0
	and dtr_concepto = 'FECI' -- 'CAP'
	and tr_tran = 'REJ'
	and tr_operacion = dtr_operacion 
	and tr_secuencial = dtr_secuencial 
	and tr_estado <> 'RV'
	and re_operacion = op_operacion
	and tr_operacion = op_operacion
	and dtr_operacion = op_operacion 
    and op_estado not in (3,0,99)
	and tr_operacion in (@w_operacionca )  #####  AQUI REEMPLAZAR LA OPERACION
) as rej
where am_operacion = operacion 
and am_concepto    = concepto 
and am_dividendo >= dividendo
-- and case when am_cuota < abs(am_gracia) and am_gracia < 0  then  1 else 0 end = 1  
and case when am_estado = 3 and am_acumulado + am_gracia - am_pagado <> 0 then 1 else 0 end = 1
limit 1000;


# R02: +- R08 Operaciones con Cuota=0 y G(-) + OP con Cuota < G(-)
select distinct 
	'R02: +- R08 Operaciones con Cuota=0 y G(-) + OP con Cuota < G(-)' as 'Regla-02',
	 op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	di_estado,
	(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
	(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
	a.*
from cob_cartera.ca_amortizacion a, cob_cartera.ca_operacion o, cob_cartera.ca_dividendo d
where am_operacion = op_operacion
and am_concepto in ( 'INT', 'FECI')
and am_operacion = di_operacion
and am_dividendo = di_dividendo
and op_operacion = op_operacion
and am_cuota  < abs(am_gracia ) 
and am_gracia < 0
and op_operacion in (@w_operacionca) -- (@w_operacionca   )  #####  AQUI REEMPLAZAR LA OPERACION
and op_estado not in (3,0,99) 
-- order by am_dividendo, am_concepto
; 

# R03: Detalle R02, +- R08 Operaciones con CERO en cuota y GRACIA NEGATIVA
select 
	'R03: Detalle R02, +- R08 Operaciones con CERO en cuota y GRACIA NEGATIVA' as 'Regla-03',
	op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	(select max(tr_tran) from cob_cartera.ca_transaccion t2 where tr_operacion = t1.op_operacion   
	 and tr_estado <> 'RV'
	 and tr_tran  IN('DES', 'RES', 'ETM','PRO', 'AJP', 'MPC',  'SUM', 'ACE', 'MAN', 'VTA','ISG','ESG','CDP','ESD','CTC','DMR','ELS','CDF','ALI','ARG','CPE','EBE') 
	) 				as 'Trn_MAN',
	(select min(tr_fecha_ref) from cob_cartera.ca_transaccion t2 where tr_operacion = t1.op_operacion   
	 and tr_estado <> 'RV'
	 and tr_tran  IN('DES', 'RES', 'ETM','PRO', 'AJP', 'MPC',  'SUM', 'ACE', 'MAN', 'VTA','ISG','ESG','CDP','ESD','CTC','DMR','ELS','CDF','ALI','ARG','CPE','EBE') 
	) 				as 'Trn_MAN_fecha_ref'
from cob_cartera.ca_operacion t1
where  op_operacion in (select op_operacion 
							from cob_cartera.ca_amortizacion am, cob_cartera.ca_operacion o
							where am_operacion = op_operacion
							and am_concepto in ( 'INT', 'FECI')
							and am_cuota  < abs(am_gracia ) 
							and am_gracia < 0
							and op_estado not in (3,0,99)
 							and op_operacion in  (@w_operacionca) -- (@w_operacionca)  #####  AQUI REEMPLAZAR LA OPERACION							
);

# R04: TRANSACCIONES PAG QUE NO CONTABILIZAN XQ LOS RUBROS SON MAYORES A LA CUENTA PUENTE
select * from (
		select 
		'R04: TRANSACCIONES PAG QUE NO CONTABILIZAN XQ LOS RUBROS SON MAYORES A LA CUENTA PUENTE' as 'Regla-04',
		op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
		tr_fecha_ref, tr_fecha_mov, tr_secuencial, tr_tran,
		sum(case when dtr_concepto = 'VAC0' then (dtr_monto ) else 0 end) as 'VAC0',
		sum(case when dtr_concepto <> 'VAC0' then (dtr_monto ) else 0 end) as 'Rubros',
		sum(case when dtr_concepto = 'VAC0' then (dtr_monto ) else 0 end)-
		sum(case when dtr_concepto <> 'VAC0' then (dtr_monto ) else 0 end) as 'Dif'
		from cob_cartera.ca_transaccion t , cob_cartera.ca_det_trn dt, ca_operacion o
		where tr_tran = 'PAG'
		and tr_estado = 'ING'
		and tr_fecha_mov <= '2024-07-26'
		and tr_operacion = dtr_operacion 
		and tr_secuencial = dtr_secuencial 
		and op_operacion = t.tr_operacion 
		and op_operacion = dtr_operacion
		# and dtr_secuencial = 48	
		and op_operacion = @w_operacionca
		group by tr_banco, tr_operacion, tr_fecha_ref, tr_secuencial, tr_tran
		) oper
where oper.Dif <> 0
order by oper.Dif;

# R05: Op CAN Di CAN Acumulado + Gracia <> Pagado
select 
'R05: Op CAN Di CAN Acumulado + Gracia <> Pagado' as'Regla-05',
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
di_estado, 
(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
a.* , oper_can.cap, oper_can.int, oper_can.feci,  oper_can.SEGCOLECAD,
case when am_acumulado = 0 then
		case when am_pagado > 0 then 
			case when am_pagado > (am_acumulado + am_gracia) then case when (am_acumulado + am_gracia) < 0 then abs( (am_acumulado + am_gracia)) else  (am_acumulado + am_gracia) end end
		else
			case when am_pagado = 0   then  
					case when (am_acumulado + am_gracia) > 0 then (am_acumulado + am_gracia) else 0 end
			else 0
			end
		end
else
	-- am_acumulado < 0 se hace el UPDATE ANTES DEL ESTO   CUOTA = ACUMULADO = 0
   -- am_acumulado > 0
		case when am_pagado > 0 then 
			case when am_pagado > (am_acumulado + am_gracia) then (am_acumulado + am_gracia) else (am_acumulado + am_gracia) end
		else
			case when am_pagado = 0   then  
					case when (am_acumulado + am_gracia) > 0 then (am_acumulado + am_gracia) else 0 end
			else 0
			end
		end
end as 'Npago'
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d, 
	(select 
		op_operacion as operacion ,  
		(select sum(am_acumulado+am_gracia-am_pagado) from cob_cartera.ca_amortizacion a1 where am_operacion = o0.op_operacion and am_concepto = 'CAP') as 'cap',
		(select sum(am_acumulado+am_gracia-am_pagado) from cob_cartera.ca_amortizacion a1 where am_operacion = o0.op_operacion and am_concepto = 'INT') as 'int',
		(select sum(am_acumulado+am_gracia-am_pagado) from cob_cartera.ca_amortizacion a1 where am_operacion = o0.op_operacion and am_concepto = 'FECI') as 'feci',
		(select sum(am_acumulado+am_gracia-am_pagado) from cob_cartera.ca_amortizacion a1 where am_operacion = o0.op_operacion and am_concepto = 'SEGCOLECAD') as 'SEGCOLECAD'		
	from cob_cartera.ca_operacion o0, cob_cartera.ca_amortizacion a0
	WHERE  o0.op_operacion = a0.am_operacion 
	and a0.am_acumulado+a0.am_gracia-a0.am_pagado <> 0 
	and o0.op_estado = 3
	AND o0.op_operacion = @w_operacionca
	group by o0.op_operacion 
	) oper_can
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and di_estado = 3
and am_acumulado+am_gracia <> am_pagado 
AND op_operacion = oper_can.operacion
;

# R06: Op ACT Rubro CAN [am_cuota <> am_acumulado] & acum > 0 & pag > 0
select 
	'R06: Op ACT Rubro CAN [am_cuota <> am_acumulado] & acum > 0 & pag > 0' as'Regla-06',
	op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
	(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
	a.* 
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and am_estado = 3
and am_cuota <> am_acumulado
and am_acumulado > 0
and am_pagado    > 0
and op_estado not in (0,99,3)
AND op_operacion = @w_operacionca
;

# R06.1: Op ACT Rub CAN [Tienen Saldo pendiente]
select 
	'R06.1: Op ACT Rub CAN [Tienen Saldo pendiente]' as'Regla-06.1',  
	op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	di_estado,
	(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
	(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
	a.* 
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and am_estado = 3
and am_acumulado + am_gracia - am_pagado  <> 0 
and op_estado not in (0,99,3)
AND op_operacion = @w_operacionca
;

# R07: Op ACT RUBROS CAN am_cuota = 0 PERO am_gracia <> 0 ABS-Gracia > Pagado
select 
'R07: Op ACT RUBROS CAN am_cuota = 0 PERO am_gracia <> 0 ABS-Gracia > Pagado' AS 'Regla-07',
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
di_estado,
a.*
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and am_cuota    = 0
and am_gracia  <> 0
and abs(am_gracia)  > am_pagado
AND op_operacion = @w_operacionca
and op_estado not in (0,99,3)
and am_estado = 3
limit 100
;

# R08: Op ACT RUBROS con am_cuota = 0 PERO am_gracia < 0  Abs(Gracia) > Pagado e HIS que no tenia CERO
select 
'R08: Op ACT RUBROS con am_cuota = 0 PERO am_gracia < 0  Abs(Gracia) > Pagado e HIS que no tenia CERO' AS 'Regla-08',
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
am_estado,
am_concepto , min(di_estado),  min(am_dividendo)
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and am_cuota   = 0
and am_gracia < 0
and abs(am_gracia)  > am_pagado
and not EXISTS (select 1 from cob_cartera.ca_amortizacion_his where amh_operacion = a.am_operacion and amh_concepto = 'FECI' and amh_dividendo = a.am_dividendo and amh_secuencial =1 and amh_cuota = 0 )
AND op_operacion = @w_operacionca
and op_estado not in (0,99,3)
GROUP by op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end, am_concepto, am_estado ;

# R09: OP con PAG y ETM NO CONTABILIZAN XQ TIENE FECI 13040
select 
'R09: OP con PAG y ETM NO CONTABILIZAN XQ TIENE FECI 13040' as 'Regla-09',
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
tr_fecha_ref, tr_secuencial, tr_tran , tr_estado, 
min(dtr_dividendo), sum(dtr_monto_mn)
from cob_cartera.ca_transaccion , cob_cartera.ca_det_trn, cob_cartera.ca_operacion o
where tr_tran in ( 'PAG', 'ETM')
and tr_estado = 'ING'
and tr_operacion = dtr_operacion 
and tr_secuencial = dtr_secuencial 
and tr_operacion = op_operacion
and dtr_codvalor = 13040
AND op_operacion = @w_operacionca
group by op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end,
tr_fecha_ref, tr_secuencial, tr_tran , tr_estado;

# R11: Op ACT Rub CAN pero son Saldo pendiente cuota<>acumulado<>pagado
select 
'R11: Op ACT Rub CAN pero son Saldo pendiente cuota<>acumulado<>pagado' as'Regla-11',  
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
di_estado, 
(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
a.* 
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and am_estado = 3
and ((am_cuota + am_gracia-am_pagado)<>0 and (am_acumulado + am_gracia-am_pagado) <> 0  )
and (am_cuota+am_gracia) <> (am_acumulado + am_gracia)
and op_estado not in (0,99,3)
AND op_operacion = @w_operacionca
;

# R11.1: Op ACT/CAN PAG NormalPry + ABExtra -> Di CAN+VEN Rub CAN con Saldo. Cuota=Acumulado >Ppagado 
select 
'R11.1: Op ACT/CAN PAG NormalPry + ABExtra -> Di CAN+VEN Rub CAN con Saldo. Cuota=Acumulado >Ppagado' as'Regla-11.1',  
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
di_estado, 
(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
a.* ,
(select max(tr_tran) from cob_cartera.ca_transaccion where tr_operacion = o.op_operacion and tr_estado <> 'RV' and tr_tran in ('CPE', 'RES')) as 'CPE'
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and di_estado in (3,2)
and am_estado = 3
and am_cuota = am_acumulado
and op_estado not in (0,99)
AND op_operacion = @w_operacionca
and (am_acumulado + am_gracia) > am_pagado  -- Luego de cancelar se incremento la cuota y acumulado
-- and am_concepto in ('INT', 'FECI')
-- and not exists (select 1 from cob_cartera.ca_transaccion where tr_operacion = o.op_operacion and tr_estado <> 'RV' and tr_tran in ('CPE', 'RES'))
;

# R12: Op ACT Di CAN+VEN Rub CAN son Saldo pendiente -> CONDO + CPE
select 
	'R12: Op ACT Di CAN+VEN Rub CAN son Saldo pendiente -> CONDO + CPE' as'Regla-12', 
	op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	di_estado, 
	(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
	(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
	a.* ,
	(select min(ab_fecha_pag) from cob_cartera.ca_abono, cob_cartera.ca_abono_det 
	    where ab_operacion = abd_operacion   and ab_secuencial_ing = abd_secuencial_ing   and ab_estado not in ('RV', 'E')     
	    and abd_tipo = 'CON'                 and abd_concepto in ('FECI', 'INT')          and ab_operacion = o.op_operacion) as 'CON 1',
	(select max(ab_fecha_pag) from cob_cartera.ca_abono, cob_cartera.ca_abono_det 
	    where ab_operacion = abd_operacion   and ab_secuencial_ing = abd_secuencial_ing   and ab_estado not in ('RV', 'E')
	    and abd_tipo = 'CON'                 and abd_concepto in ('FECI', 'INT')	        and ab_operacion = o.op_operacion) as 'CON 2',
	(select min(tr_fecha_ref) from cob_cartera.ca_transaccion 	where tr_operacion = o.op_operacion and tr_estado <> 'RV' 	
	and tr_tran in( 'CPE', 'RES')  )                                                                                         as 'CPE-RES' ,
	(select min(tr_fecha_ref) from cob_cartera.ca_abono a, cob_cartera.ca_abono_det , cob_cartera.ca_transaccion 
	   where ab_operacion = abd_operacion   and ab_secuencial_ing = abd_secuencial_ing   and ab_estado not in ('RV', 'E')
		and abd_tipo = 'CON'                  and abd_concepto in ('FECI', 'INT')
		and ab_operacion = o.op_operacion     and tr_secuencial > ab_secuencial_pag 	and tr_operacion = o.op_operacion and tr_estado <> 'RV' 
		and tr_tran IN('DES','RES','ETM','PRO','AJP','MPC','SUM','ACE','MAN','VTA','ISG','ESG','CDP','ESD','CTC','DMR','ELS','ALI','ARG','VTA','RCO','MIG') 
	   and ab_operacion = o.op_operacion)                                                                                     as 'Trn MAN'
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and di_estado in (3,2)
and am_estado = 3
and ((am_acumulado + am_gracia) <> am_pagado  )
and op_estado not in (0,99,3)
AND op_operacion = @w_operacionca
and exists(select 1 from cob_cartera.ca_abono a, cob_cartera.ca_abono_det 
    where ab_operacion = abd_operacion
   and ab_secuencial_ing = abd_secuencial_ing
	and ab_estado not in ('RV', 'E')
	and abd_tipo = 'CON'
	and abd_concepto in ('FECI', 'INT')
	and ab_operacion = o.op_operacion
	and ab_secuencial_pag <= ifnull((select min(tr_secuencial) from cob_cartera.ca_transaccion 
												where tr_operacion = o.op_operacion and tr_estado <> 'RV' 
												and tr_tran in( 'CPE', 'RES')  and  a.ab_fecha_pag <> tr_fecha_ref ),
												ab_secuencial_pag))
and am_concepto in ('FECI', 'INT');



# R13: Op ACT Div VIG Pagado > acumulado + gracia(+)
select 
'R13: Op ACT Div VIG Pagado > acumulado + gracia(+)' as'Regla-13',  
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
di_estado, 
(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
a.* , di_fecha_ini, di_fecha_ven, op_migrada, op_fecha_ult_proceso, (select min('CPE') from cob_cartera.ca_transaccion where tr_operacion = o.op_operacion and tr_estado <> 'RV' and tr_tran in ('CPE', 'RES')) as 'Trn'
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
and di_estado in (1)
and am_estado not in (3,4)
and (am_acumulado + am_gracia) < am_pagado
and am_gracia >= 0
and op_estado not in (0,99,3)
AND op_operacion = @w_operacionca
;


# R14: Op ACT con CPE Div CAN Rub CAN son Saldo pendiente
select 
	'R14: Op ACT con CPE Div CAN Rub CAN son Saldo pendiente' as'Regla-14', 
	op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	di_estado,
	(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
	(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
	a.* ,
	(select min(ab_fecha_pag) from cob_cartera.ca_abono, cob_cartera.ca_abono_det 
	    where ab_operacion = abd_operacion   and ab_secuencial_ing = abd_secuencial_ing   and ab_estado not in ('RV', 'E')     
	    and abd_tipo = 'CON'                 and abd_concepto in ('FECI', 'INT')          and ab_operacion = o.op_operacion) as 'CON 1',
	(select max(ab_fecha_pag) from cob_cartera.ca_abono, cob_cartera.ca_abono_det 
	    where ab_operacion = abd_operacion   and ab_secuencial_ing = abd_secuencial_ing   and ab_estado not in ('RV', 'E')
	    and abd_tipo = 'CON'                 and abd_concepto in ('FECI', 'INT')	        and ab_operacion = o.op_operacion) as 'CON 2',
	(select min(tr_fecha_ref) from cob_cartera.ca_transaccion 	where tr_operacion = o.op_operacion and tr_estado <> 'RV' 	
	and tr_tran in( 'CPE', 'RES')  )                                                                                         as 'CPE-RES' ,
	(select min(tr_fecha_ref) from cob_cartera.ca_abono a, cob_cartera.ca_abono_det , cob_cartera.ca_transaccion 
	   where ab_operacion = abd_operacion     and ab_secuencial_ing = abd_secuencial_ing   and ab_estado not in ('RV', 'E')
		and abd_tipo = 'CON'                   and abd_concepto in ('FECI', 'INT')          and ab_operacion = o.op_operacion
		and tr_secuencial > ab_secuencial_pag 	and tr_operacion = o.op_operacion            and tr_estado <> 'RV' 
		and tr_tran IN('DES','RES','ETM','PRO','AJP','MPC','SUM','ACE','MAN','VTA','ISG',
		               'ESG','CDP','ESD','CTC','DMR','ELS','ALI','ARG','VTA','RCO','MIG') 
	   and ab_operacion = o.op_operacion)                                                                                     as 'Trn MAN',
	   tr_secuencial, tr_tran,
	   (
	      SELECT case when am_pagado > 0 and am_acumulado = 0 then 'caso_JUAN' else              '.'	      end 
	      FROM cob_cartera.ca_amortizacion 
	      WHERE am_operacion = o.op_operacion
	      AND am_concepto    = a.am_concepto
	      AND am_dividendo   = (
				      SELECT amh_dividendo + 1
				      FROM cob_cartera.ca_amortizacion_his a2, cob_cartera.ca_dividendo_his d2
				      WHERE a2.amh_secuencial = transaccion.tr_secuencial
				      AND a2.amh_operacion = o.op_operacion
				      AND d2.dih_secuencial = transaccion.tr_secuencial
				      AND d2.dih_operacion = o.op_operacion
				      AND d2.dih_dividendo = a2.amh_dividendo
				      AND a2.amh_concepto = a.am_concepto
				      AND d2.dih_estado = 1)
	   )                                                                                                                       as 'Juan', 
	   (
	      SELECT 
	             case when am_pagado > 0 and am_cuota <> am_acumulado and am_acumulado > 0 then 'caso_LGU' else '.' end
	      FROM cob_cartera.ca_amortizacion 
	      WHERE am_operacion = o.op_operacion
	      AND am_concepto    = a.am_concepto
	      AND am_dividendo   = (
				      SELECT amh_dividendo 
				      FROM cob_cartera.ca_amortizacion_his a2, cob_cartera.ca_dividendo_his d2
				      WHERE a2.amh_secuencial = transaccion.tr_secuencial
				      AND a2.amh_operacion = o.op_operacion
				      AND d2.dih_secuencial = transaccion.tr_secuencial
				      AND d2.dih_operacion = o.op_operacion
				      AND d2.dih_dividendo = a2.amh_dividendo
				      AND a2.amh_concepto = a.am_concepto
				      AND d2.dih_estado = 1)
	   )	                                                                                                                     as 'Lgu',
	   or_aplicar	, or_capitaliza, op_toperacion, op_tipo_amortizacion
from cob_cartera.ca_operacion o, cob_cartera.ca_amortizacion a, cob_cartera.ca_dividendo d, 
		( select distinct  tr_secuencial, tr_operacion, tr_tran, or_aplicar	, or_capitaliza 
		  from cob_cartera.ca_transaccion t, cob_credito.cr_op_renovar r
		  where tr_secuencial > 0 and tr_estado <> 'RV' and tr_tran in( 'CPE', 'RES') 
		  and tr_banco = or_num_operacion and or_finalizo_renovacion = 'S'
		  and tr_fecha_ref = or_fecha_concesion
		  AND tr_operacion = @w_operacionca
		) transaccion
WHERE  op_operacion = am_operacion 
and op_operacion = di_operacion
and am_dividendo = di_dividendo
-- and di_estado = 3
and am_estado = 3
and ((am_acumulado + am_gracia - am_pagado) <> 0  )
and op_estado not in (0,99,3)
and tr_operacion = op_operacion
order by am_operacion, am_dividendo, am_concepto 
 ;

# R15: Op ACT Rub CAN son Saldo pendiente PAG OK acumulado <> cuota
select r15.* from 
(
	select 
		'R15: Op ACT Rub CAN son Saldo pendiente PAG OK acumulado <> cuota' as'Regla-15', 
		op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
		di_estado, 
		(am_cuota + am_gracia - am_pagado )     as 'Saldo_proy',
		(am_acumulado + am_gracia - am_pagado ) as 'Saldo_acum',
		a.* , (select  sum(tp_monto) from cob_cartera.ca_transaccion_prv tr 
					where tp_operacion = o.op_operacion 
					and tp_dividendo = d.di_dividendo 
					and tp_concepto = a.am_concepto 
					group by tp_concepto,tp_dividendo) as 'PRV'
	from cob_cartera.ca_amortizacion a, cob_cartera.ca_operacion o, cob_cartera.ca_dividendo d
	where am_operacion = op_operacion  and am_concepto in ('INT', 'FECI') and am_dividendo > 0  
	and am_acumulado + am_gracia - am_pagado <> 0 
	and am_cuota     + am_gracia - am_pagado =  0 
	and op_estado not in (0,99,3)
	and di_operacion  = am_operacion 
	and di_dividendo  = am_dividendo 
	and am_estado     = 3
	and op_operacion = di_operacion
	AND op_operacion = @w_operacionca
) as r15
where Saldo_acum + am_cuota = PRV
order by am_operacion, am_dividendo, am_concepto 
 ;

# R17: Descuadre CAP entre OP y AM
select
'R17: Descuadre CAP entre OP y AM ' as'Regla-17',
(his.op_monto - his.am_capital ) as'Dif_OP_AM',
(his.ro_valor - his.am_capital ) as'Dif_RO_AM',
(his.op_monto - his.ro_valor ) as'Dif_OP_RO',
his.*
from (
	select
	oph_secuencial, tr_tran, tr_estado, date(tr_fecha_ref) as tr_fecha_ref, tr_fecha_real,
	oph_banco, oph_operacion, oph_tipo_amortizacion, oph_toperacion,
	max(oph_estado) as 'oph_estado', max(oph_monto) as 'op_monto',
	sum(amh_cuota) +
	ifnull((select sum(am_cuota) from cob_cartera.ca_amortizacion where am_operacion = t.tr_operacion
	and am_concepto = 'CAP' and am_dividendo >= 1 and am_dividendo < min(amh_dividendo) and min(amh_dividendo) > 1 ),0) as 'am_capital',
	min(amh_dividendo) as 'div_ini', max(amh_dividendo) as 'div_fin',
	(select max(roh_valor) from cob_cartera.ca_rubro_op_his r where roh_operacion = t.tr_operacion
	and roh_concepto = 'CAP' and roh_secuencial = t.tr_secuencial) as 'ro_valor'
	from cob_cartera.ca_operacion_his o, cob_cartera.ca_amortizacion_his a, cob_cartera.ca_transaccion t
	where oph_operacion = amh_operacion
	and oph_operacion in (@w_operacionca) ##### AQUI REEMPLAZAR LA OPERACION
	and amh_concepto = 'CAP'
	and oph_secuencial = amh_secuencial
	and tr_operacion = o.oph_operacion
	and tr_secuencial = o.oph_secuencial
	and tr_estado <> 'RV'
	GROUP by oph_banco, oph_operacion, oph_tipo_amortizacion, oph_toperacion, oph_secuencial, tr_tran, tr_estado, tr_fecha_ref, tr_fecha_real
	UNION
	select
	99999, 'HOY', 'HOY', 'HOY', 'HOY',
	op_banco, op_operacion, op_tipo_amortizacion, op_toperacion,
	op_estado, max(op_monto), sum(am_cuota), min(am_dividendo), max(am_dividendo), max(ro_valor)
	from cob_cartera.ca_operacion, cob_cartera.ca_amortizacion , ca_rubro_op
	where op_operacion = am_operacion
	and op_operacion in (@w_operacionca ) ##### AQUI REEMPLAZAR LA OPERACION
	and am_concepto = 'CAP'
	and op_operacion = ro_operacion
	and ro_concepto = 'CAP'
	GROUP by op_banco, op_operacion, op_tipo_amortizacion, op_toperacion, op_estado
	order by 6, 1
) as his # ejecutar hasta aqui para ver el detalle
where (his.op_monto <> his.am_capital )
;


# R17.2: Descuadre CAP entre RO y AM
select
'R17.2: Descuadre CAP entre RO y AM ' as'Regla-17.2',
(his.ro_valor - his.am_capital ) as'Dif_RO_AM',
(his.op_monto - his.am_capital ) as'Dif_OP_AM',
(his.op_monto - his.ro_valor ) as'Dif_OP_RO',
his.*
from (
select
oph_secuencial, tr_tran, tr_estado, date(tr_fecha_ref) as tr_fecha_ref, tr_fecha_real,
oph_banco, oph_operacion, oph_tipo_amortizacion, oph_toperacion,
max(oph_estado) as 'oph_estado', max(roh_valor) as 'ro_valor',
sum(amh_cuota) +
ifnull((select sum(am_cuota) from cob_cartera.ca_amortizacion where am_operacion = t.tr_operacion
and am_concepto = 'CAP' and am_dividendo >= 1 and am_dividendo < min(amh_dividendo) and min(amh_dividendo) > 1 ),0) as 'am_capital',
min(amh_dividendo) as 'div_ini', max(amh_dividendo) as 'div_fin', max(oph_monto) as op_monto
from cob_cartera.ca_operacion_his o, cob_cartera.ca_amortizacion_his a, cob_cartera.ca_transaccion t, cob_cartera.ca_rubro_op_his r
where oph_operacion = amh_operacion
and oph_operacion in ( @w_operacionca ) ##### AQUI REEMPLAZAR LA OPERACION
and amh_concepto = 'CAP'
and oph_secuencial = amh_secuencial
and tr_operacion = o.oph_operacion
and tr_secuencial = o.oph_secuencial
and tr_estado <> 'RV'
and oph_operacion = roh_operacion
and oph_secuencial= r.roh_secuencial
and roh_concepto = 'CAP'
GROUP by oph_banco, oph_operacion, oph_tipo_amortizacion, oph_toperacion, oph_secuencial, tr_tran, tr_estado, tr_fecha_ref, tr_fecha_real
UNION
select
99999, 'HOY', 'HOY', 'HOY', 'HOY',
op_banco, op_operacion, op_tipo_amortizacion, op_toperacion,
op_estado,max(ro_valor), sum(am_cuota), min(am_dividendo), max(am_dividendo), max(op_monto)
from cob_cartera.ca_operacion, cob_cartera.ca_amortizacion , cob_cartera.ca_rubro_op
where op_operacion = am_operacion
and op_operacion in ( @w_operacionca ) ##### AQUI REEMPLAZAR LA OPERACION
and am_concepto = 'CAP'
and op_operacion = ro_operacion
and ro_concepto = 'CAP'
GROUP by op_banco, op_operacion, op_tipo_amortizacion, op_toperacion, op_estado
order by 7, 1
) as his # ejecutar hasta aqui para ver el detalle
where (his.ro_valor <> his.am_capital )
;

# R18: Descuadre Sumatoria-Gracia <> 0 en DIARIAS
select 
'R18: Descuadre Sumatoria-Gracia <> 0 en DIARIAS' as'Regla-18', 
op_banco, op_operacion, op_estado,   op_tipo_amortizacion,	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
am_concepto, gracia
from (
	select 
	 am_operacion, am_concepto, sum(am_gracia) as gracia
	from cob_cartera.ca_amortizacion 
	where am_concepto in ('FECI', 'INT')
	and am_operacion = @w_operacionca
	-- and am_gracia <> 0
	group by  am_operacion , am_concepto
	having sum(am_gracia)<> 0
) as r18, ca_operacion 
where op_operacion = am_operacion
limit 100;


# R18.1: detalle DE R18/ Descuadre Sumatoria-Gracia <> 0 en HISTORICOS
select 
   'R18.1: detalle DE R18/ Descuadre Sumatoria-Gracia <> 0 en HISTORICOS' as'Regla-18.2', 
	op_banco, operacion, op_estado, op_tipo_amortizacion, op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	amh_concepto,  gracia, 
	( select tr_secuencial from ca_transaccion t join ca_operacion_his o on tr_operacion = oph_operacion and oph_secuencial = tr_secuencial 
	  where tr_secuencial < minimo 
	  and tr_operacion = tmp2.operacion
	  and tr_estado <> 'RV'
	  and tr_tran   <> 'RPA'
	  and t.tr_secuencial > 0  order by tr_fecha_ref desc, abs(tr_secuencial) desc limit 1) as 'Sec-daño',
	minimo as 'Sec-min', 
	maximo as 'Sec-max',
	( select CONCAT_WS("-",tr_tran , tr_estado ,date(tr_fecha_ref ))
	  from ca_transaccion t join ca_operacion_his o ON tr_operacion = oph_operacion and oph_secuencial = tr_secuencial 
	  where tr_secuencial < minimo 
	  and tr_operacion = tmp2.operacion
	  and tr_estado <> 'RV'
	  and tr_tran <> 'RPA'
	  and t.tr_secuencial > 0  order by tr_fecha_ref desc, abs(tr_secuencial) desc limit 1) as 'Trn-daño',
	(select CONCAT_WS("-", tr_tran , tr_estado , date(tr_fecha_ref )) from cob_cartera.ca_transaccion where tr_operacion = tmp2.operacion and tr_secuencial = minimo ) as 'Trn-min',
	(select CONCAT_WS("-", tr_tran , tr_estado , date(tr_fecha_ref )) from cob_cartera.ca_transaccion where tr_operacion = tmp2.operacion and tr_secuencial = maximo ) as 'Trn-max',
	( select tr_tran 
	  from ca_transaccion t join ca_operacion_his o on tr_operacion = oph_operacion and oph_secuencial = tr_secuencial 
	  where tr_secuencial < minimo 
	  and tr_operacion = tmp2.operacion
	  and tr_estado <> 'RV'
	  and tr_tran <> 'RPA'
	  and t.tr_secuencial > 0 order by tr_fecha_ref desc, abs(tr_secuencial) desc limit 1) as 'Tran-daño'
from 
	(
	select  operacion, amh_concepto,  gracia, min(amh_secuencial)  as 'minimo', max(amh_secuencial) as 'maximo'
	from 
		(
		select
			amh_operacion as 'operacion', amh_concepto, sum(amh_gracia) as gracia, amh_secuencial 
		from cob_cartera.ca_amortizacion_his a
		join cob_cartera.ca_operacion_his  o ON amh_operacion = oph_operacion and amh_secuencial = oph_secuencial
		join cob_cartera.ca_transaccion t   ON tr_operacion = oph_operacion   and t.tr_secuencial = o.oph_secuencial 
		join (
				select 
				 am_operacion as operacion, am_concepto as concepto
				from cob_cartera.ca_amortizacion 
				where am_concepto in ('FECI', 'INT')
				and am_operacion = @w_operacionca
				and am_gracia <> 0
				group by  am_operacion , am_concepto
				having sum(am_gracia)<> 0 
			) as tmp0 on a.amh_operacion = tmp0.operacion and a.amh_concepto = tmp0.concepto
		where amh_operacion = tmp0.operacion
		and amh_gracia <> 0
		and tr_estado  <> 'RV'
		and tr_tran    <> 'RPA'
		and tr_secuencial > 0
		group by amh_secuencial, amh_operacion, amh_concepto
		having sum(amh_gracia)<> 0
		) as tmp
	group by operacion, amh_concepto,  gracia
	) as tmp2,
	ca_operacion 
where operacion = op_operacion
;


######## ENCONTRAR DONDE SE DESCUADRO LA GRACIA
# R18.2: detalle DE R18/ Descuadre Sumatoria-Gracia <> 0 en HISTORICOS
select
'R18.2: detalle DE R18/ Descuadre Sumatoria-Gracia <> 0 en HISTORICOS' as'Regla-18.2',
amh_secuencial, oph_banco, amh_operacion, oph_estado, amh_concepto, sum(amh_gracia) as gracia,
(select max(tr_secuencial) from ca_transaccion where tr_operacion = o.oph_operacion and tr_secuencial < o.oph_secuencial ) as 'Sec_trn'
from cob_cartera.ca_amortizacion_his, cob_cartera.ca_operacion_his o
where amh_concepto in ('FECI', 'INT')
and amh_operacion = @w_operacionca
and amh_operacion = oph_operacion
and amh_secuencial = oph_secuencial
and amh_gracia <> 0
group by amh_secuencial, oph_banco, amh_operacion, oph_estado, amh_concepto
having sum(amh_gracia)<> 0
LIMIT 100
;

# R20: Reajustes en TManuales que incremento Gracia
select * from (
select 
	'R20: Reajustes en TManuales que incremento Gracia ' as'Regla-20', 
	t1.*, 
	(select sum(amh_gracia) from ca_amortizacion_his where amh_operacion = t1.op_operacion and amh_secuencial = t1.tr_secuencial  ) as 'GraciaAntes',
	case when t1.tr_siguiente  = 99999 
	then
	(select sum(am_gracia) from ca_amortizacion where am_operacion = t1.op_operacion  ) 
	else
	(select sum(amh_gracia) from ca_amortizacion_his where amh_operacion = t1.op_operacion and amh_secuencial = t1.tr_siguiente  ) 
	end 
	as 'GraciaDespues' 
from 	
	(
	select 
	op_banco, op_operacion, op_estado,   op_tipo_amortizacion as 'TamorHoy',	op_toperacion,  case when op_migrada is null then 'COBIS' else 'MIGRADA' end as 'origen',
	tr_fecha_ref, 
	tr_fecha_mov, 
	tr_secuencial , 
	ifnull((select min(tr_secuencial) 
		from ca_transaccion, ca_operacion_his 
		where tr_operacion = oph_operacion 
		and tr_secuencial = oph_secuencial 
		and tr_estado <> 'RV' 
		and tr_tran    <> 'RPA'
		and tr_secuencial > 0
		and tr_operacion = o.op_operacion 
		and tr_secuencial > t.tr_secuencial),99999) as 'tr_siguiente'
	from ca_operacion o , ca_transaccion t, ca_operacion_his oh
	where tr_operacion = op_operacion 
	and tr_operacion in (@w_operacionca)
	and tr_tran = 'REJ'
	and tr_estado  <> 'RV'
	and tr_tran    <> 'RPA'
	and tr_secuencial > 0
	and tr_fecha_mov >= '2025-01-05'
	and op_operacion = oph_operacion
	and tr_operacion = oph_operacion
	and tr_secuencial = oph_secuencial 
	and oph_tipo_amortizacion = 'MANUAL'
	) as t1
) as t2
where GraciaAntes <> GraciaDespues
order by op_banco, tr_fecha_mov;




##############################################################################################################################################################
-- SCRIPTS VALIDACION OPERACIONES OK 
##############################################################################################################################################################

# R1: Cancelados con saldo
-- Cancelados con saldo  en ca_corrige_gracia
SELECT r.* FROM (
select 'R1: Cancelados con saldo' as 'Regla', op_banco, a.* from ca_amortizacion a, ca_operacion o
where am_operacion in (select cg_operacion  from ca_corrige_gracia where cg_estado = 'F' and cg_resultado = 'OK')
and am_operacion = op_operacion
and am_estado = 3
and am_acumulado + am_gracia - am_pagado <> 0
 ) AS r where r.op_banco in (@w_banco);
 
# R2: G(-) mayor que cuota en proceso corrige_gracia
-- G(-) mayor que cuota en proceso corrige_gracia
select r.* from (
select 'R2: G(-) mayor que cuota en proceso corrige_gracia' as 'Regla', op_banco, a.* from ca_amortizacion a, ca_operacion o
where am_operacion in (select cg_operacion  from ca_corrige_gracia where cg_estado = 'F'  and cg_resultado = 'OK')
and am_operacion = op_operacion
and am_gracia < 0
and am_cuota < abs(am_gracia)
) as r where r.op_banco in (@w_banco);
 
# R3: suma Gracia <> CERO
-- suma Gracia <> CERO
select 'R3: suma Gracia <> CERO' as 'Regla', op_banco, am_operacion, sum(am_gracia) from ca_amortizacion a, ca_operacion o
where am_operacion in (select cg_operacion  from ca_corrige_gracia where cg_estado = 'F'  and cg_resultado = 'OK')
and am_operacion = op_operacion
group by op_banco, am_operacion
having sum(am_gracia) <> 0;
 
#R4: Cancelados con saldo 
-- Cancelados con saldo en ca_corrige_cuotagracia_canc
select 'R4: Cancelados con saldo' as 'Regla', op_banco, a.* from ca_amortizacion a, ca_operacion o
where am_operacion in (select cg_operacion  from ca_corrige_cuotagracia_canc where cg_estado = 'F' and cg_resultado = 'OK')
and am_operacion = op_operacion
and am_estado = 3
and am_acumulado + am_gracia - am_pagado <> 0;
 
# R5: G(-) mayor que cuota en proceso corrige_gracia
-- G(-) mayor que cuota en proceso corrige_gracia
select r.* from (
select 'R5: G(-) mayor que cuota en proceso corrige_gracia' as 'Regla', op_banco, a.* from ca_amortizacion a, ca_operacion o
where am_operacion in (select cg_operacion  from ca_corrige_cuotagracia_canc where cg_estado = 'F'  and cg_resultado = 'OK')
and am_operacion = op_operacion
and am_gracia < 0
and am_cuota < abs(am_gracia)
) as r where r.op_banco in (@w_banco);
 
# R6: suma Gracia <> CERO
-- suma Gracia <> CERO
select 'R6: suma Gracia <> CERO' as 'Regla', op_banco, am_operacion, sum(am_gracia) from ca_amortizacion a, ca_operacion o
where am_operacion in (select cg_operacion  from ca_corrige_cuotagracia_canc where cg_estado = 'F'  and cg_resultado = 'OK')
and am_operacion = op_operacion
group by op_banco, am_operacion
having sum(am_gracia) <> 0;
 
 
#R7: Cancelados con saldo
-- Cancelados con saldo en tablas diarias
select 'R7: Cancelados con saldo' as 'Regla', op_banco, a.* from ca_amortizacion a, ca_operacion o
where am_operacion in (select op_operacion  from ca_operacion where op_operacion in (@w_operacionca))
and am_operacion = op_operacion
and am_estado = 3
and am_acumulado + am_gracia - am_pagado <> 0;
 
# R8: G(-) mayor que cuota en proceso corrige_gracia
-- G(-) mayor que cuota en proceso corrige_gracia
select 'R8: G(-) mayor que cuota en proceso corrige_gracia' as 'Regla', op_banco, a.* from ca_amortizacion a, ca_operacion o
where am_operacion in (select op_operacion  from ca_operacion where  op_operacion in (@w_operacionca))
and am_operacion = op_operacion
and am_gracia < 0
and am_cuota < abs(am_gracia);
 
# R9: suma Gracia <> CERO
-- suma Gracia <> CERO
select 'R9: suma Gracia <> CERO' as 'Regla',op_banco, am_operacion, sum(am_gracia) from ca_amortizacion a, ca_operacion o
where am_operacion in (select op_operacion  from ca_operacion where  op_operacion in (@w_operacionca))
and am_operacion = op_operacion
group by op_banco, am_operacion
having sum(am_gracia) <> 0;