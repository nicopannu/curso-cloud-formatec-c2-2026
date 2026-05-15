-- Soluciones/Servicios
insert into solutions (name, description, strategy_hint) values
('Hosting corporativo', 'Sitios institucionales con soporte tecnico y backup nocturno.', 'Replatform futuro: S3 + CloudFront'),
('Servidores administrados', 'VMs gestionadas para aplicaciones empresariales.', 'Rehost inicial: EC2'),
('Respaldo remoto', 'Copias periodicas hacia storage externo.', 'Replatform futuro: S3 + lifecycle'),
('Consultoria cloud', 'Evaluacion de migracion, costos y continuidad.', 'Discovery + matriz 6R')
on conflict do nothing;

-- Clientes historicos con datos criticos
-- IMPORTANTE: Estos datos incluyen informacion encriptada y deben migrarse con cuidado
insert into customers (customer_code, company_name, contact_name, email, phone, encrypted_credit_card, encrypted_tax_id, contract_start_date, contract_end_date, total_spent, is_active) values
('CUST-2018-001', 'Bodegas del Valle SA', 'Maria Rodriguez', 'mrodriguez@bodegasdelvalle.com', '+54-261-4567890',
    pgp_sym_encrypt('4532-1234-5678-9010', 'cloudcuyo-secret-key-2018'),
    pgp_sym_encrypt('30-71234567-8', 'cloudcuyo-secret-key-2018'),
    '2018-03-15', '2026-03-15', 245800.50, true),

('CUST-2019-002', 'Viñedos Andinos SRL', 'Carlos Gomez', 'cgomez@vinedosandinos.com', '+54-261-4321098',
    pgp_sym_encrypt('5425-9876-5432-1098', 'cloudcuyo-secret-key-2018'),
    pgp_sym_encrypt('30-69876543-2', 'cloudcuyo-secret-key-2018'),
    '2019-06-20', '2027-06-20', 189500.75, true),

('CUST-2020-003', 'Consultora TechMza', 'Laura Fernandez', 'lfernandez@techmza.com', '+54-261-4445566',
    pgp_sym_encrypt('4916-1111-2222-3333', 'cloudcuyo-secret-key-2018'),
    pgp_sym_encrypt('30-71112233-4', 'cloudcuyo-secret-key-2018'),
    '2020-01-10', null, 320450.00, true),

('CUST-2017-004', 'Olivares del Sur', 'Roberto Sanchez', 'rsanchez@olivaresdelsur.com', '+54-261-4778899',
    pgp_sym_encrypt('4024-4567-8901-2345', 'cloudcuyo-secret-key-2018'),
    pgp_sym_encrypt('30-78901234-5', 'cloudcuyo-secret-key-2018'),
    '2017-11-05', '2025-11-05', 412300.25, true),

('CUST-2021-005', 'Inmobiliaria Cuyo Real', 'Patricia Lopez', 'plopez@cuyoreal.com', '+54-261-4998877',
    pgp_sym_encrypt('3782-9999-8888-7777', 'cloudcuyo-secret-key-2018'),
    pgp_sym_encrypt('30-79998887-7', 'cloudcuyo-secret-key-2018'),
    '2021-04-22', null, 156700.00, true),

('CUST-2016-006', 'Distribuidora Martinez e Hijos', 'Juan Martinez', 'jmartinez@distmartinez.com', '+54-261-4112233',
    pgp_sym_encrypt('5105-1050-5050-0001', 'cloudcuyo-secret-key-2018'),
    pgp_sym_encrypt('30-61122334-4', 'cloudcuyo-secret-key-2018'),
    '2016-08-30', '2024-08-30', 567890.00, false)
on conflict do nothing;

-- Servicios contratados por clientes
insert into customer_services (customer_id, solution_id, contracted_date, monthly_cost, status) values
(1, 1, '2018-03-15', 15000.00, 'active'),
(1, 2, '2018-03-15', 28000.00, 'active'),
(2, 1, '2019-06-20', 12000.00, 'active'),
(2, 3, '2019-06-20', 8500.00, 'active'),
(3, 2, '2020-01-10', 35000.00, 'active'),
(3, 4, '2020-01-10', 25000.00, 'active'),
(4, 1, '2017-11-05', 18000.00, 'active'),
(4, 2, '2017-11-05', 32000.00, 'active'),
(4, 3, '2017-11-05', 10000.00, 'active'),
(5, 1, '2021-04-22', 14000.00, 'active'),
(5, 2, '2021-04-22', 22000.00, 'active'),
(6, 2, '2016-08-30', 30000.00, 'cancelled')
on conflict do nothing;

-- Historial de pagos (datos historicos criticos para migracion)
-- Solo insertamos algunos pagos de ejemplo, en produccion habria cientos/miles
insert into payment_history (customer_id, amount, payment_date, payment_method, transaction_id, status, notes) values
(1, 43000.00, '2024-01-15', 'credit_card', 'TRX-2024-001-43K', 'completed', 'Pago mensual enero 2024'),
(1, 43000.00, '2024-02-15', 'credit_card', 'TRX-2024-002-43K', 'completed', 'Pago mensual febrero 2024'),
(1, 43000.00, '2024-03-15', 'credit_card', 'TRX-2024-003-43K', 'completed', 'Pago mensual marzo 2024'),
(2, 20500.00, '2024-01-20', 'bank_transfer', 'TRX-2024-004-20K', 'completed', 'Pago mensual enero 2024'),
(2, 20500.00, '2024-02-20', 'bank_transfer', 'TRX-2024-005-20K', 'completed', 'Pago mensual febrero 2024'),
(3, 60000.00, '2024-01-10', 'credit_card', 'TRX-2024-006-60K', 'completed', 'Pago mensual enero 2024'),
(3, 60000.00, '2024-02-10', 'credit_card', 'TRX-2024-007-60K', 'completed', 'Pago mensual febrero 2024'),
(4, 60000.00, '2024-01-05', 'bank_transfer', 'TRX-2024-008-60K', 'completed', 'Pago mensual enero 2024'),
(4, 60000.00, '2024-02-05', 'bank_transfer', 'TRX-2024-009-60K', 'completed', 'Pago mensual febrero 2024'),
(5, 36000.00, '2024-01-22', 'credit_card', 'TRX-2024-010-36K', 'completed', 'Pago mensual enero 2024'),
(5, 36000.00, '2024-02-22', 'credit_card', 'TRX-2024-011-36K', 'completed', 'Pago mensual febrero 2024')
on conflict do nothing;

-- Paginas legacy
insert into legacy_pages (slug, title, active, migration_strategy) values
('promo-hosting-2009', 'Promocion Hosting 2009', false, 'retire'),
('clientes-legacy', 'Acceso Clientes Legacy', true, 'retain'),
('buzon', 'Buzon de Contacto', true, 'refactor')
on conflict do nothing;
