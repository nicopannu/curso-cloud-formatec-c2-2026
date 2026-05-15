-- Extension para encriptacion
create extension if not exists pgcrypto;

-- Tabla de soluciones/servicios
create table if not exists solutions (
    id serial primary key,
    name text not null unique,
    description text not null,
    strategy_hint text not null
);

-- Tabla de contactos
create table if not exists contacts (
    id serial primary key,
    name text not null,
    email text not null,
    category text not null,
    message text not null,
    created_at timestamptz not null default now()
);

-- Tabla de clientes (datos criticos, historicos)
create table if not exists customers (
    id serial primary key,
    customer_code text not null unique,
    company_name text not null,
    contact_name text not null,
    email text not null,
    phone text,
    -- Datos encriptados (tarjeta de credito, informacion sensible)
    encrypted_credit_card bytea,
    encrypted_tax_id bytea,
    contract_start_date date not null,
    contract_end_date date,
    total_spent numeric(12, 2) default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Tabla de servicios contratados por clientes
create table if not exists customer_services (
    id serial primary key,
    customer_id integer not null references customers(id) on delete cascade,
    solution_id integer not null references solutions(id) on delete restrict,
    contracted_date date not null,
    monthly_cost numeric(10, 2) not null,
    status text not null default 'active' check (status in ('active', 'suspended', 'cancelled')),
    created_at timestamptz not null default now()
);

-- Tabla de historial de pagos (datos historicos importantes)
create table if not exists payment_history (
    id serial primary key,
    customer_id integer not null references customers(id) on delete cascade,
    amount numeric(10, 2) not null,
    payment_date date not null,
    payment_method text not null,
    transaction_id text not null unique,
    status text not null default 'completed' check (status in ('completed', 'pending', 'failed', 'refunded')),
    notes text,
    created_at timestamptz not null default now()
);

-- Tabla de paginas legacy (para ejercicio de RETIRE)
create table if not exists legacy_pages (
    id serial primary key,
    slug text not null unique,
    title text not null,
    active boolean not null default true,
    migration_strategy text not null
);

-- Indices para mejor performance
create index idx_customers_customer_code on customers(customer_code);
create index idx_customers_email on customers(email);
create index idx_customer_services_customer_id on customer_services(customer_id);
create index idx_payment_history_customer_id on payment_history(customer_id);
create index idx_payment_history_payment_date on payment_history(payment_date desc);

-- Permisos
grant all privileges on all tables in schema public to cloudcuyo;
grant all privileges on all sequences in schema public to cloudcuyo;
