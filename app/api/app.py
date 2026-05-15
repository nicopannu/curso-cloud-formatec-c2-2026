import os

import psycopg2
from flask import Flask, jsonify, request
from flask_cors import CORS


app = Flask(__name__)
CORS(app)


def db_config():
    return {
        "host": os.getenv("DB_HOST", "192.168.56.40"),
        "dbname": os.getenv("DB_NAME", "cloudcuyo"),
        "user": os.getenv("DB_USER", "cloudcuyo"),
        "password": os.getenv("DB_PASSWORD", "cloudcuyo"),
    }


def query(sql, params=None, fetch=True):
    with psycopg2.connect(**db_config()) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or [])
            if not fetch:
                return None
            return cur.fetchall()


@app.get("/api/health")
def health():
    try:
        query("select 1")
        database = "ok"
    except Exception as exc:
        database = f"error: {exc}"
    return jsonify({"status": "ok", "node": os.getenv("APP_NODE", "api01"), "database": database})


@app.get("/api/solutions")
def solutions():
    rows = query("select name, description, strategy_hint from solutions order by id")
    return jsonify([
        {"name": row[0], "description": row[1], "strategy_hint": row[2]}
        for row in rows
    ])


@app.post("/api/contact")
def contact():
    payload = request.get_json(force=True)
    name = payload.get("name", "").strip()
    email = payload.get("email", "").strip()
    category = payload.get("category", "ventas").strip()
    message = payload.get("message", "").strip()

    if not name or not email or not message:
        return jsonify({"error": "name, email and message are required"}), 400

    rows = query(
        """
        insert into contacts (name, email, category, message)
        values (%s, %s, %s, %s)
        returning id
        """,
        [name, email, category, message],
    )
    return jsonify({"id": rows[0][0], "status": "stored"}), 201


@app.get("/api/messages")
def messages():
    rows = query("select id, name, email, category, created_at from contacts order by id desc limit 20")
    return jsonify([
        {"id": r[0], "name": r[1], "email": r[2], "category": r[3], "created_at": r[4].isoformat()}
        for r in rows
    ])


@app.get("/api/customers")
def customers():
    """
    Lista de clientes activos con informacion basica (sin datos encriptados).
    Los datos encriptados (tarjetas, tax_id) NO se exponen en la API publica.
    """
    rows = query("""
        select
            customer_code,
            company_name,
            contact_name,
            email,
            contract_start_date,
            total_spent,
            is_active
        from customers
        where is_active = true
        order by customer_code
    """)
    return jsonify([
        {
            "customer_code": r[0],
            "company_name": r[1],
            "contact_name": r[2],
            "email": r[3],
            "contract_start_date": r[4].isoformat(),
            "total_spent": float(r[5]),
            "is_active": r[6]
        }
        for r in rows
    ])


@app.get("/api/customers/<customer_code>/services")
def customer_services(customer_code):
    """
    Servicios contratados por un cliente especifico.
    """
    rows = query("""
        select
            s.name,
            cs.contracted_date,
            cs.monthly_cost,
            cs.status
        from customer_services cs
        join customers c on cs.customer_id = c.id
        join solutions s on cs.solution_id = s.id
        where c.customer_code = %s
        order by cs.contracted_date desc
    """, [customer_code])

    if not rows:
        return jsonify({"error": "Customer not found or no services"}), 404

    return jsonify([
        {
            "service_name": r[0],
            "contracted_date": r[1].isoformat(),
            "monthly_cost": float(r[2]),
            "status": r[3]
        }
        for r in rows
    ])


@app.get("/api/stats")
def stats():
    """
    Estadisticas generales del sistema (para demostrar datos historicos).
    """
    total_customers = query("select count(*) from customers where is_active = true")[0][0]
    total_revenue = query("select coalesce(sum(total_spent), 0) from customers")[0][0]
    total_payments = query("select count(*) from payment_history where status = 'completed'")[0][0]

    return jsonify({
        "total_active_customers": total_customers,
        "total_revenue": float(total_revenue),
        "total_completed_payments": total_payments,
        "database_status": "operational"
    })


@app.post("/api/auth/login")
def login():
    """
    Autenticacion legacy simple por codigo de cliente + email.
    En AWS: migrar a Cognito o API Gateway + Lambda authorizer.
    """
    payload = request.get_json(force=True)
    customer_code = payload.get("customer_code", "").strip()
    email = payload.get("email", "").strip().lower()

    if not customer_code or not email:
        return jsonify({"error": "customer_code and email are required"}), 400

    rows = query("""
        select
            id, customer_code, company_name, contact_name, email,
            contract_start_date, total_spent, is_active
        from customers
        where customer_code = %s and lower(email) = %s and is_active = true
    """, [customer_code, email])

    if not rows:
        return jsonify({"error": "Invalid credentials or inactive account"}), 401

    row = rows[0]
    return jsonify({
        "status": "authenticated",
        "customer": {
            "id": row[0],
            "customer_code": row[1],
            "company_name": row[2],
            "contact_name": row[3],
            "email": row[4],
            "contract_start_date": row[5].isoformat(),
            "total_spent": float(row[6]),
            "is_active": row[7]
        }
    })


@app.get("/api/customers/<customer_code>/payments")
def customer_payments(customer_code):
    """
    Historial de pagos del cliente (ultimos 10).
    """
    rows = query("""
        select
            ph.id,
            ph.amount,
            ph.payment_date,
            ph.payment_method,
            ph.transaction_id,
            ph.status,
            ph.notes
        from payment_history ph
        join customers c on ph.customer_id = c.id
        where c.customer_code = %s
        order by ph.payment_date desc, ph.id desc
        limit 10
    """, [customer_code])

    if not rows:
        return jsonify([])

    return jsonify([
        {
            "id": r[0],
            "amount": float(r[1]),
            "payment_date": r[2].isoformat(),
            "payment_method": r[3],
            "transaction_id": r[4],
            "status": r[5],
            "notes": r[6]
        }
        for r in rows
    ])


# ============================================================================
# PUBLIC API v1 - APIs expuestas a clientes externos (pasan por LB)
# ============================================================================

@app.get("/api/v1/customers/<customer_code>/status")
def public_customer_status(customer_code):
    """
    API publica: estado de servicios para integraciones externas.
    Usada por clientes para monitoreo automatizado.
    """
    # Validar que el cliente existe
    customer_rows = query("""
        select id, company_name, is_active
        from customers
        where customer_code = %s
    """, [customer_code])

    if not customer_rows:
        return jsonify({"error": "Customer not found"}), 404

    customer_id, company_name, is_active = customer_rows[0]

    if not is_active:
        return jsonify({
            "customer_code": customer_code,
            "company_name": company_name,
            "status": "inactive",
            "services": []
        })

    # Obtener servicios activos
    service_rows = query("""
        select
            s.name,
            cs.status,
            cs.monthly_cost
        from customer_services cs
        join solutions s on cs.solution_id = s.id
        where cs.customer_id = %s and cs.status = 'active'
        order by cs.contracted_date
    """, [customer_id])

    return jsonify({
        "customer_code": customer_code,
        "company_name": company_name,
        "status": "active",
        "services": [
            {
                "name": r[0],
                "status": r[1],
                "monthly_cost": float(r[2])
            }
            for r in service_rows
        ],
        "api_version": "v1",
        "note": "This API will be migrated to AWS API Gateway + Lambda"
    })


@app.get("/api/v1/customers/<customer_code>/billing")
def public_customer_billing(customer_code):
    """
    API publica: informacion de facturacion resumida.
    """
    rows = query("""
        select
            c.company_name,
            c.total_spent,
            c.is_active,
            coalesce(sum(cs.monthly_cost), 0) as monthly_total
        from customers c
        left join customer_services cs on c.id = cs.customer_id and cs.status = 'active'
        where c.customer_code = %s
        group by c.id, c.company_name, c.total_spent, c.is_active
    """, [customer_code])

    if not rows:
        return jsonify({"error": "Customer not found"}), 404

    row = rows[0]
    return jsonify({
        "customer_code": customer_code,
        "company_name": row[0],
        "total_spent": float(row[1]),
        "current_monthly_cost": float(row[2]),
        "is_active": row[3],
        "api_version": "v1",
        "note": "This API will be migrated to AWS API Gateway + Lambda"
    })


@app.get("/api/v1/health")
def public_health():
    """
    Health check publico para monitoreo externo.
    """
    try:
        query("select 1")
        db_status = "healthy"
    except Exception:
        db_status = "unhealthy"

    return jsonify({
        "status": "ok",
        "node": os.getenv("APP_NODE", "api01"),
        "database": db_status,
        "api_version": "v1",
        "migration_status": "pending_aws_migration"
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
