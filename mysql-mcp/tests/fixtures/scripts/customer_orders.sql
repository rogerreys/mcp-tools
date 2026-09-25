# fixture script for test_server_integration.py::run_script tests
SELECT @cust_id:=1;

SELECT id, full_name, email FROM customers WHERE id = @cust_id;

SELECT o.id, o.status, o.total_cents
FROM orders o
WHERE o.customer_id = @cust_id  #### AQUI REEMPLAZAR EL CLIENTE
ORDER BY o.id;
