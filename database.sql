-- ======================================================================
-- ЖЕТКІЗІЛІМДЕРДІ ЕСЕПКЕ АЛУ ЖҮЙЕСІ («ЖабдықТасқын»)
-- Supply Management Database
-- Дереккөз: Еркінұлы Олжас курстық жұмысы (3.1, 3.2 тараулар негізінде)
-- ======================================================================

CREATE DATABASE IF NOT EXISTS supply_management
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE supply_management;

-- ----------------------------------------------------------------------
-- 1. Жеткізушілер (suppliers)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS suppliers (
    supplier_id     INT AUTO_INCREMENT PRIMARY KEY,
    company_name    VARCHAR(200) NOT NULL,
    contact_person  VARCHAR(150),
    phone           VARCHAR(20),
    email           VARCHAR(100),
    address         VARCHAR(255),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_name (company_name)
);

-- ----------------------------------------------------------------------
-- 2. Қоймалар (warehouses)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS warehouses (
    warehouse_id    INT AUTO_INCREMENT PRIMARY KEY,
    warehouse_name  VARCHAR(150) NOT NULL,
    location        VARCHAR(255),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------
-- 3. Материалдар (materials)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS materials (
    material_id     INT AUTO_INCREMENT PRIMARY KEY,
    article         VARCHAR(30) NOT NULL UNIQUE,
    material_name   VARCHAR(200) NOT NULL,
    unit            VARCHAR(20) NOT NULL,           -- шт, м, л ...
    unit_price      DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    min_stock       DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
    current_stock   DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (current_stock >= 0),
    warehouse_id    INT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    INDEX idx_material_name (material_name)
);

-- ----------------------------------------------------------------------
-- 4. Тапсырыстар (orders)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    order_id        INT AUTO_INCREMENT PRIMARY KEY,
    order_number    VARCHAR(30) NOT NULL UNIQUE,     -- мыс. PO-2025-00003
    supplier_id     INT NOT NULL,
    warehouse_id    INT NOT NULL,
    status          ENUM('draft','confirmed','received','cancelled') DEFAULT 'draft',
    order_date      DATE DEFAULT (CURRENT_DATE),
    expected_date   DATE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_status (status),
    INDEX idx_expected (expected_date)
);

-- ----------------------------------------------------------------------
-- 5. Тапсырыс позициялары (order_items)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_items (
    order_item_id   INT AUTO_INCREMENT PRIMARY KEY,
    order_id        INT NOT NULL,
    material_id     INT NOT NULL,
    quantity        DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit_price      DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (material_id) REFERENCES materials(material_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------
-- 6. Қалдық қозғалыстары (stock_movements)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stock_movements (
    movement_id     INT AUTO_INCREMENT PRIMARY KEY,
    material_id     INT NOT NULL,
    warehouse_id    INT NOT NULL,
    move_type       ENUM('receipt','issue','adjustment') NOT NULL,
    quantity        DECIMAL(12,2) NOT NULL,
    notes           VARCHAR(255),
    moved_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (material_id) REFERENCES materials(material_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_moved_at (moved_at)
);

-- ----------------------------------------------------------------------
-- 7. Ескертулер (alerts)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS alerts (
    alert_id        INT AUTO_INCREMENT PRIMARY KEY,
    alert_type      ENUM('low_stock','overdue_delivery') NOT NULL,
    material_id     INT,
    order_id        INT,
    message         VARCHAR(255) NOT NULL,
    is_resolved     TINYINT(1) DEFAULT 0,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (material_id) REFERENCES materials(material_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    INDEX idx_resolved (is_resolved)
);

-- ======================================================================
-- ТРИГГЕРЛЕР (3.1-бөлім)
-- ======================================================================
DELIMITER $$

-- 1. Тапсырыс алынды -> қалдықты жаңарту + қозғалыс жазу
CREATE TRIGGER trg_order_received
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF NEW.status = 'received' AND OLD.status != 'received' THEN
        UPDATE materials m
        INNER JOIN order_items oi ON oi.material_id = m.material_id
        SET m.current_stock = m.current_stock + oi.quantity
        WHERE oi.order_id = NEW.order_id;

        INSERT INTO stock_movements
            (material_id, warehouse_id, move_type, quantity, notes)
        SELECT oi.material_id, NEW.warehouse_id, 'receipt',
               oi.quantity, CONCAT('Тапсырыс ', NEW.order_number)
        FROM order_items oi
        WHERE oi.order_id = NEW.order_id;
    END IF;
END$$

-- 2. Қалдық минимумнан төмен -> ескерту
CREATE TRIGGER trg_low_stock_alert
AFTER UPDATE ON materials
FOR EACH ROW
BEGIN
    IF NEW.current_stock < NEW.min_stock
       AND OLD.current_stock >= OLD.min_stock THEN
        INSERT INTO alerts (alert_type, material_id, message)
        VALUES ('low_stock', NEW.material_id,
                CONCAT('«', NEW.material_name, '» қалдығы минимумнан төмен: ',
                       NEW.current_stock));
    END IF;
END$$

DELIMITER ;

-- ======================================================================
-- БАСТАПҚЫ ДЕРЕКТЕР (SEED DATA) — 3.1, 3.2-кестелер
-- ======================================================================

INSERT INTO warehouses (warehouse_name, location) VALUES
('Орталық қойма', 'Астана, өнеркәсіптік аймақ, 1-ғимарат'),
('Қосалқы қойма', 'Астана, өнеркәсіптік аймақ, 2-ғимарат');

INSERT INTO suppliers (company_name, contact_person, phone, email) VALUES
('ТОО «МеталлТрейд»',     'Қасымов Нұрлан',    '+77011112233', 'kasymov@mt.kz'),
('ТОО «ЭлектроКомплект»', 'Иванова Светлана',  '+77022223344', 'ivanova@ek.kz'),
('ТОО «ГидроСистема»',    'Бектасов Серік',    '+77033334455', 'bektasov@gs.kz'),
('ТОО «ХимРесурс»',       'Смағұлова Айгүл',   '+77044445566', 'smagul@hr.kz'),
('ТОО «ТехноПарт»',       'Дюсенов Марат',     '+77055556677', 'dyusenov@tp.kz');

INSERT INTO materials (article, material_name, unit, unit_price, min_stock, current_stock, warehouse_id) VALUES
('MTL-001', 'Болт М12x50',        'шт', 85.00,   500, 750,  1),
('MTL-002', 'Гайка М12',          'шт', 45.00,   500, 1200, 1),
('MTL-003', 'Швеллер 120x65',     'м',  8500.00, 20,  15,   1),
('ELC-001', 'Кабель ВВГ 3x2.5',   'м',  320.00,  100, 80,   2),
('ELC-002', 'Автомат выключатель 32А', 'шт', 2100.00, 50, 45, 2),
('HYD-001', 'Гидравликалық май HLP46', 'л', 850.00, 100, 95, 2);

INSERT INTO orders (order_number, supplier_id, warehouse_id, status, order_date, expected_date) VALUES
('PO-2025-00001', 1, 1, 'received',  '2025-05-01', '2025-05-10'),
('PO-2025-00002', 2, 2, 'received',  '2025-05-05', '2025-05-15'),
('PO-2025-00003', 2, 2, 'confirmed', '2025-05-20', '2025-05-28'),
('PO-2025-00004', 3, 2, 'draft',     '2025-06-01', '2025-06-12'),
('PO-2025-00005', 4, 2, 'confirmed', '2025-06-03', '2025-06-14');

INSERT INTO order_items (order_id, material_id, quantity, unit_price) VALUES
(1, 1, 500, 85.00),
(1, 2, 800, 45.00),
(2, 4, 200, 320.00),
(3, 5, 60,  2100.00),
(5, 6, 50,  850.00);

-- Ескерту мысалдары (аз қалдық + кешіктірілген жеткізілім)
INSERT INTO alerts (alert_type, material_id, order_id, message) VALUES
('low_stock', 3, NULL, '«Швеллер 120x65» қалдығы минимумнан төмен: 15'),
('low_stock', 4, NULL, '«Кабель ВВГ 3x2.5» қалдығы минимумнан төмен: 80'),
('low_stock', 5, NULL, '«Автомат выключатель 32А» қалдығы минимумнан төмен: 45'),
('overdue_delivery', NULL, 3, 'PO-2025-00003 тапсырысы кешіктірілді');

-- ======================================================================
-- SQL СҰРАНЫСТАРЫ (3.2-бөлім) — көрсетілім/есеп үшін VIEW ретінде
-- ======================================================================

-- 1. Аз қалдықтағы материалдар
CREATE OR REPLACE VIEW v_low_stock AS
SELECT material_id, article, material_name, current_stock, min_stock, unit
FROM materials
WHERE current_stock < min_stock
ORDER BY (current_stock / min_stock) ASC;

-- 2. Жеткізуші бойынша тапсырыстар саны және жалпы сомасы
CREATE OR REPLACE VIEW v_supplier_totals AS
SELECT s.company_name,
       COUNT(o.order_id) AS order_count,
       SUM(oi.quantity * oi.unit_price) AS total_amount
FROM suppliers s
JOIN orders o ON o.supplier_id = s.supplier_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'received'
GROUP BY s.supplier_id, s.company_name
ORDER BY total_amount DESC;

-- 3. Соңғы 30 күндегі қозғалыстар
CREATE OR REPLACE VIEW v_recent_movements AS
SELECT sm.moved_at, m.material_name, w.warehouse_name,
       sm.move_type, sm.quantity, sm.notes
FROM stock_movements sm
JOIN materials m ON m.material_id = sm.material_id
JOIN warehouses w ON w.warehouse_id = sm.warehouse_id
WHERE sm.moved_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY sm.moved_at DESC;

-- 4. Шешілмеген ескертулер
CREATE OR REPLACE VIEW v_unresolved_alerts AS
SELECT a.alert_id, a.alert_type, m.material_name, o.order_number,
       a.message, a.created_at
FROM alerts a
LEFT JOIN materials m ON m.material_id = a.material_id
LEFT JOIN orders o ON o.order_id = a.order_id
WHERE a.is_resolved = FALSE
ORDER BY a.created_at DESC;

-- 5. Расталған, бірақ мерзімі өткен тапсырыстар
CREATE OR REPLACE VIEW v_overdue_orders AS
SELECT order_id, order_number, expected_date,
       DATEDIFF(CURDATE(), expected_date) AS days_overdue
FROM orders
WHERE status IN ('draft','confirmed')
  AND expected_date < CURDATE()
ORDER BY days_overdue DESC;
