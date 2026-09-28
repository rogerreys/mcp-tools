SELECT @op:= 143308, @banco:= '0000579599', @sec_ing:= 1280;

 --                                        DATOS DE LA OPERACION
SELECT op.op_cliente,op.op_nombre, @banco := op_banco as banco, @op:= op_operacion as op, op.op_migrada, op_reestructuracion,op_estado,
op_monto, @w_fecha_mov:=op_fecha_ult_proceso as op_fecha_ult_proceso, op_fecha_ini, op_fecha_fin, op_estado, op_tipo_amortizacion, op.op_toperacion, op.*
FROM cob_cartera.ca_operacion op WHERE
op_banco IN (@banco) and
op_operacion = @op
;

--		dividendo
SELECT di_estado, d.* from cob_cartera.ca_dividendo d  where di_operacion = @op and di_estado = 1
;
-- Estado
SELECT * FROM cob_cartera.ca_estado ce 
;

-- 	ca_operacion_his
SELECT h.* FROM cob_cartera.ca_operacion_his h where oph_operacion = @op
;
--  	ca_log_fecha_valor 
select * from cob_cartera.ca_log_fecha_valor where fv_operacion in (@op)
;

-- 			ca_abono_prioridad
SELECT DISTINCT ap_prioridad, ap_concepto FROM cob_cartera.ca_abono_prioridad p WHERE ap_operacion = @op 
AND ap_secuencial_ing = 1773
ORDER BY ap_prioridad
;

--			ca_amortizacion 
select * from ca_amortizacion where am_operacion = @op
;
SELECT am_operacion,am_acumulado+am_gracia-am_pagado AS 'PAGADO', ca.* 
from cob_cartera.ca_amortizacion ca where am_operacion = @op 
and ca.am_concepto IN ('FECI') -- 'CAP', 'INT' 
;

-- 			ca_amortizacion_his
SELECT sum(amh_cuota), amh_secuencial 
from cob_cartera.ca_amortizacion_his cah where amh_operacion = @op 
and amh_concepto in ("CAP") -- 'INT' , 'FECI',
;
SELECT amh_secuencial, amh_operacion, amh_estado, amh_dividendo, sum(amh_pagado) AS 'PAGADO'
from cob_cartera.ca_amortizacion_his cah where amh_operacion = @op -- and amh_secuencial = 1268
and amh_dividendo between 195 and 199
and amh_estado <> 0
group by amh_secuencial, amh_dividendo
;
-- 		ca_abono_det
select dtr_dividendo, dtr_concepto, SUBSTRING(es_descripcion, 1, 10) AS descripcion_corta,
TRIM(dtr_cuenta) AS cuenta, SUBSTRING(CONCAT(CAST(mo_moneda AS CHAR), '-', mo_descripcion), 1, 10) AS moneda_descripcion,
dtr_monto, dtr_monto_mn, dtr_cotizacion
from  cob_cartera.ca_det_trn, cob_cartera.ca_estado, cobis.cl_moneda
where dtr_estado     = es_codigo 
and   dtr_operacion  = @op
and   dtr_moneda     = mo_moneda
;
-- 		ca_abono  vs  ca_abono_det
select ab_estado, ab_secuencial_ing, ab_secuencial_pag,ab_secuencial_rpa, ab_fecha_ing, ab_fecha_pag, ab_usuario,
   ab_oficina, ab_dias_retencion, ab_solo_cap, ab_aceptar_anticipos, ab_tipo_reduccion,
   ab_tipo_cobro, abd_tipo, abd_concepto, abd_moneda,
   substring(abd_cuenta,1,24), substring(abd_beneficiario,1,50),
   abd_monto_mpg
from  ca_abono, ca_abono_det
where ab_operacion = @op
and   ab_operacion = abd_operacion
and   ab_secuencial_ing = abd_secuencial_ing
order by abd_operacion, ab_secuencial_ing desc

--		ca_abono
-- SELECT ab_estado, a.* FROM cob_cartera.ca_abono a WHERE ab_operacion = @op AND ab_estado IN('ING','NA') ORDER BY ab_secuencial_ing;
SELECT ab_estado, @sec:=case when ab_estado = 'A' then ab_secuencial_pag else ab_secuencial_pag*-1 end as ab_secuencial_pag,a.* 
FROM cob_cartera.ca_abono a WHERE ab_operacion = @op AND ab_tipo IN('PAG') and  ab_secuencial_ing = @sec_ing ORDER BY ab_secuencial_ing;
--		ca_abono_det
SELECT * FROM cob_cartera.ca_abono_det where abd_operacion = @op and abd_secuencial_ing in (@sec_ing)
;
-- 		ca_det_trn
SELECT d.* FROM cob_cartera.ca_det_trn d where dtr_operacion = @op and dtr_secuencial = @sec
;
--		dividendo
SELECT d.* from cob_cartera.ca_dividendo d  where di_operacion = @op and di_dividendo >= @div
;
SELECT di_operacion, @div_max:=max(cd.di_dividendo), @div_vig:=ifnull(di_dividendo,0) from cob_cartera.ca_dividendo cd  where di_operacion = @op and di_estado = 1;
SELECT dih_operacion, dih_secuencial, max(cd.dih_dividendo) from cob_cartera.ca_dividendo_his cd  where dih_operacion = @op group by cd.dih_secuencial;

-- 		ca_dividendo_his
SELECT dih_estado, h.* FROM cob_cartera.ca_dividendo_his h where dih_operacion = @op and dih_dividendo in (197,198); 

SELECT dih_estado, h.* FROM cob_cartera.ca_dividendo_his h where dih_operacion = @op and h.dih_secuencial = @sec_ing; 

-- 		ca_rubro_op
SELECT ro_valor, ro_porcentaje, r.* FROM cob_cartera.ca_rubro_op r where ro_operacion = @op AND ro_concepto IN ("FECI") -- 'INT', 'CAP'
;
-- 		ca_rubro_op_his
SELECT roh_valor, roh_porcentaje, h.* FROM cob_cartera.ca_rubro_op_his h where roh_operacion = @op AND roh_concepto ="FECI"
;
-- 		ca_reajuste
SELECT @w_sec_reaj := re_secuencial as sec_rej, r.* FROM cob_cartera.ca_reajuste r WHERE re_operacion = @op
-- AND re_secuencial = @sec_ing; 
;

--  	ca_reajuste_det
SELECT * FROM cob_cartera.ca_reajuste_det d WHERE red_operacion = @op AND red_secuencial=@w_sec_reaj
;
-- ca_reajuste & ca_reajuste_det
SELECT red_concepto, red_porcentaje, r.*, d.*
FROM ca_reajuste r JOIN ca_reajuste_det d ON red_operacion = re_operacion AND red_secuencial = re_secuencial
WHERE (re_fecha >= @w_fecha_mov or re_fecha >= @w_fecha) AND re_operacion = @op
;
--		transaccion
SELECT @w_sec_trn := tr_secuencial as sec, tr_secuencial_ref, tr_estado, tr_tran, tr_fecha_ref,tr_fecha_mov, t.* 
FROM cob_cartera.ca_transaccion t 
where tr_operacion = @op 
and tr_secuencial = @sec_ing
;
--      transaccion_prv
SELECT * FROM ca_transaccion_prv where tp_operacion = @op
;
-- 		ca_det_trn
SELECT @div := dtr_dividendo as 'div', d.* FROM cob_cartera.ca_det_trn d 
where dtr_operacion = @op and dtr_secuencial = @sec_ing
;

--      DESEMBOLSO
SELECT dm_fecha_ingreso, d.* FROM ca_desembolso d where dm_operacion = @op
;

-- 		transaccion vs reajuste - FV  
SELECT @fecha_init:= '2026-07-03', @fecha_fin:= '2026-07-22'; -- AAAA-MM-DD 
SELECT tr_secuencial, tr_fecha_ref, tr_fecha_mov, tr_toperacion, tr_tran, tr_operacion FROM cob_cartera.ca_transaccion  
WHERE (tr_operacion = @op AND ((tr_secuencial >= 1 AND "F" = 'F') OR (tr_secuencial > 1 AND "F" = 'R')) AND tr_estado <> 'RV'  
AND (tr_tran IN('DES','RES','ETM','PRO','AJP','MPC','SUM','ACE','MAN','VTA','ISG','ESG','CDP','ESD','CTC','DMR','ELS','CDF','ALI','ARG','CPE','EBE','IOC','AIO') 
OR  EXISTS(
	SELECT 1 FROM cob_cartera.ca_reajuste
	WHERE (re_operacion = @op AND re_fecha > @fecha_init 
	AND re_fecha < @fecha_fin AND re_desagio = 'm'))
));
--		ca_trn_manual
SELECT * FROM cob_cartera.ca_trn_manual WHERE (tm_operacion = @op AND tm_fecha_aplicacion < @fecha_fin AND tm_estado = 'NA')
;
--		subsidio
SELECT * FROM cob_cartera.ca_subsidio cs where cs.su_operacion in (@op)
;
-- beneficio
SELECT bt_tfeci_ant, bt_beneficio_feci, bt_beneficio_tinteres, @w_fecha:=bt_fecha as fecha,@w_fecha_mov:=bt_fecha_mov as fecha_mov,  b.* 
FROM cob_cartera.ca_beneficio_tercera_edad b WHERE bt_operacion in (@op)
;
-- ca_otro_cargo
SELECT * FROM cob_cartera.ca_otro_cargo where oc_operacion in (@op)
;
