-- Sample schema + data for testing mysql-mcp-server's exploration tools.

CREATE TABLE customers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(120) NOT NULL,
    email VARCHAR(160) NOT NULL UNIQUE,
    phone VARCHAR(40),
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    status ENUM('pending', 'paid', 'shipped', 'cancelled') NOT NULL DEFAULT 'pending',
    total_cents INT NOT NULL,
    shipping_address VARCHAR(255),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
    INDEX idx_orders_status (status)
);

CREATE TABLE order_items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_name VARCHAR(160) NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price_cents INT NOT NULL,
    CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders(id)
);

INSERT INTO customers (full_name, email, phone, notes) VALUES
    ('Ana Torres', 'ana.torres@example.com', '+56 9 1111 1111', 'Cliente frecuente, prefiere envío express'),
    ('Bruno Silva', 'bruno.silva@example.com', '+56 9 2222 2222', 'Contactar solo por email'),
    ('Carla Nuñez', 'carla.nunez@example.com', NULL, 'Pidió factura con RUT empresa'),
    ('Diego Rojas', 'diego.rojas@example.com', '+56 9 4444 4444', NULL);

INSERT INTO orders (customer_id, status, total_cents, shipping_address) VALUES
    (1, 'paid', 45990, 'Av. Siempre Viva 742, Santiago'),
    (1, 'shipped', 12990, 'Av. Siempre Viva 742, Santiago'),
    (2, 'pending', 89990, 'Calle Falsa 123, Valparaíso'),
    (3, 'cancelled', 15990, 'Pasaje Los Aromos 45, Concepción');

INSERT INTO order_items (order_id, product_name, quantity, unit_price_cents) VALUES
    (1, 'Teclado mecánico', 1, 45990),
    (2, 'Mouse inalámbrico', 1, 12990),
    (3, 'Monitor 27 pulgadas', 1, 89990),
    (4, 'Cable HDMI 2m', 2, 7995);
