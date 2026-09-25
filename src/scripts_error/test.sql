select @id := 123;
select * from clientes where id=@id;
select * from pedidos where cliente_id=@id and estado=@estado;