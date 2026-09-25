# fixture script for test_server_integration.py: must be rejected wholesale
SELECT @cust_id:=1;

SELECT id, full_name FROM customers WHERE id = @cust_id;

UPDATE customers SET full_name = 'hacked' WHERE id = @cust_id;
