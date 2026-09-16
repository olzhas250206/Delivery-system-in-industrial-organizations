"""
app.py
Жеткізілімдерді есепке алу жүйесі («ЖабдықТасқын») — Flask бэкенд
Дереккөз: Еркінұлы Олжас курстық жұмысы (3.3.1-бөлім негізінде)

Іске қосу:
    pip install flask mysql-connector-python
    python app.py
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
from decimal import Decimal
from datetime import date, datetime

app = Flask(__name__)
CORS(app)

# ----------------------------------------------------------------------
# Дерекқор конфигурациясы
# ----------------------------------------------------------------------
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",          # өз құпия сөзіңізді енгізіңіз
    "database": "supply_management",
    "charset": "utf8mb4",
}


def get_connection():
    """MySQL дерекқорына қосылым орнату."""
    return mysql.connector.connect(**DB_CONFIG)


# ----------------------------------------------------------------------
# JSON сериализациясы (Decimal және datetime түрлерін түрлендіру)
# ----------------------------------------------------------------------
def serialize(obj):
    if isinstance(obj, list):
        return [serialize(item) for item in obj]
    if isinstance(obj, dict):
        result = {}
        for key, value in obj.items():
            if isinstance(value, Decimal):
                result[key] = float(value)
            elif isinstance(value, (datetime, date)):
                result[key] = value.isoformat()
            else:
                result[key] = value
        return result
    return obj


# ----------------------------------------------------------------------
# Жалпы CRUD көмекші функциялары
# ----------------------------------------------------------------------
def query(sql, params=None, fetch_one=False):
    """SELECT сұранысын орындап, нәтижені JSON-ға дайын түрде қайтарады."""
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(sql, params or ())
        rows = cursor.fetchone() if fetch_one else cursor.fetchall()
        return serialize(rows)
    finally:
        cursor.close()
        conn.close()


def execute(sql, params=None):
    """INSERT / UPDATE / DELETE сұранысын орындайды."""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(sql, params or ())
        conn.commit()
        return cursor.lastrowid
    finally:
        cursor.close()
        conn.close()


# ----------------------------------------------------------------------
# Exception өңдегіш — кез келген қате JSON форматында қайтарылады
# ----------------------------------------------------------------------
@app.errorhandler(Exception)
def handle_error(e):
    return jsonify({"error": str(e)}), 500


# ========================================================================
# 1. /api/dashboard — жалпы статистика және соңғы ескертулер
# ========================================================================
@app.route("/api/dashboard", methods=["GET"])
def dashboard():
    stats = {
        "materials_count": query(
            "SELECT COUNT(*) AS c FROM materials", fetch_one=True)["c"],
        "suppliers_count": query(
            "SELECT COUNT(*) AS c FROM suppliers", fetch_one=True)["c"],
        "orders_count": query(
            "SELECT COUNT(*) AS c FROM orders", fetch_one=True)["c"],
        "pending_count": query(
            "SELECT COUNT(*) AS c FROM orders WHERE status IN ('draft','confirmed')",
            fetch_one=True)["c"],
        "low_stock_count": query(
            "SELECT COUNT(*) AS c FROM materials WHERE current_stock < min_stock",
            fetch_one=True)["c"],
        "active_alerts_count": query(
            "SELECT COUNT(*) AS c FROM alerts WHERE is_resolved = FALSE",
            fetch_one=True)["c"],
    }
    recent_alerts = query(
        """SELECT alert_id, alert_type, message, created_at
           FROM alerts
           WHERE is_resolved = FALSE
           ORDER BY created_at DESC
           LIMIT 10"""
    )
    return jsonify({"stats": stats, "recent_alerts": recent_alerts})


# ========================================================================
# 2. /api/suppliers — жеткізушілер CRUD
# ========================================================================
@app.route("/api/suppliers", methods=["GET"])
def get_suppliers():
    rows = query(
        "SELECT * FROM suppliers ORDER BY company_name ASC")
    return jsonify(rows)


@app.route("/api/suppliers", methods=["POST"])
def add_supplier():
    data = request.get_json()
    new_id = execute(
        """INSERT INTO suppliers (company_name, contact_person, phone, email, address)
           VALUES (%s, %s, %s, %s, %s)""",
        (data["company_name"], data.get("contact_person"),
         data.get("phone"), data.get("email"), data.get("address")))
    return jsonify({"supplier_id": new_id}), 201


@app.route("/api/suppliers/<int:supplier_id>", methods=["PUT"])
def update_supplier(supplier_id):
    data = request.get_json()
    execute(
        """UPDATE suppliers
           SET company_name=%s, contact_person=%s, phone=%s, email=%s, address=%s
           WHERE supplier_id=%s""",
        (data["company_name"], data.get("contact_person"),
         data.get("phone"), data.get("email"), data.get("address"), supplier_id))
    return jsonify({"status": "ok"})


@app.route("/api/suppliers/<int:supplier_id>", methods=["DELETE"])
def delete_supplier(supplier_id):
    # MySQL жағында ON DELETE RESTRICT белсенді тапсырыстары бар жеткізушіні
    # жоюға тыйым салады — қате JSON форматында errorhandler арқылы қайтады.
    execute("DELETE FROM suppliers WHERE supplier_id=%s", (supplier_id,))
    return jsonify({"status": "deleted"})


# ========================================================================
# 3. /api/materials — материалдар CRUD
# ========================================================================
@app.route("/api/materials", methods=["GET"])
def get_materials():
    rows = query(
        "SELECT * FROM materials ORDER BY material_name ASC")
    return jsonify(rows)


@app.route("/api/materials", methods=["POST"])
def add_material():
    data = request.get_json()
    new_id = execute(
        """INSERT INTO materials
           (article, material_name, unit, unit_price, min_stock, current_stock, warehouse_id)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (data["article"], data["material_name"], data["unit"],
         data["unit_price"], data.get("min_stock", 0),
         data.get("current_stock", 0), data.get("warehouse_id")))
    return jsonify({"material_id": new_id}), 201


@app.route("/api/materials/<int:material_id>", methods=["PUT"])
def update_material(material_id):
    data = request.get_json()
    execute(
        """UPDATE materials
           SET article=%s, material_name=%s, unit=%s, unit_price=%s,
               min_stock=%s, current_stock=%s, warehouse_id=%s
           WHERE material_id=%s""",
        (data["article"], data["material_name"], data["unit"],
         data["unit_price"], data.get("min_stock", 0),
         data.get("current_stock", 0), data.get("warehouse_id"), material_id))
    return jsonify({"status": "ok"})


@app.route("/api/materials/<int:material_id>", methods=["DELETE"])
def delete_material(material_id):
    execute("DELETE FROM materials WHERE material_id=%s", (material_id,))
    return jsonify({"status": "deleted"})


# ========================================================================
# 4. /api/warehouses — қоймалар CRUD
# ========================================================================
@app.route("/api/warehouses", methods=["GET"])
def get_warehouses():
    rows = query("SELECT * FROM warehouses ORDER BY warehouse_name ASC")
    return jsonify(rows)


@app.route("/api/warehouses", methods=["POST"])
def add_warehouse():
    data = request.get_json()
    new_id = execute(
        "INSERT INTO warehouses (warehouse_name, location) VALUES (%s, %s)",
        (data["warehouse_name"], data.get("location")))
    return jsonify({"warehouse_id": new_id}), 201


@app.route("/api/warehouses/<int:warehouse_id>", methods=["PUT"])
def update_warehouse(warehouse_id):
    data = request.get_json()
    execute(
        "UPDATE warehouses SET warehouse_name=%s, location=%s WHERE warehouse_id=%s",
        (data["warehouse_name"], data.get("location"), warehouse_id))
    return jsonify({"status": "ok"})


@app.route("/api/warehouses/<int:warehouse_id>", methods=["DELETE"])
def delete_warehouse(warehouse_id):
    execute("DELETE FROM warehouses WHERE warehouse_id=%s", (warehouse_id,))
    return jsonify({"status": "deleted"})


# ========================================================================
# 5. /api/orders — тапсырыстар CRUD + "Алынды" деп белгілеу
# ========================================================================
@app.route("/api/orders", methods=["GET"])
def get_orders():
    rows = query(
        """SELECT o.*, s.company_name, w.warehouse_name
           FROM orders o
           JOIN suppliers s ON s.supplier_id = o.supplier_id
           JOIN warehouses w ON w.warehouse_id = o.warehouse_id
           ORDER BY o.order_date DESC""")
    return jsonify(rows)


@app.route("/api/orders", methods=["POST"])
def add_order():
    data = request.get_json()
    new_id = execute(
        """INSERT INTO orders (order_number, supplier_id, warehouse_id, status, expected_date)
           VALUES (%s, %s, %s, %s, %s)""",
        (data["order_number"], data["supplier_id"], data["warehouse_id"],
         data.get("status", "draft"), data.get("expected_date")))
    return jsonify({"order_id": new_id}), 201


@app.route("/api/orders/<int:order_id>", methods=["PUT"])
def update_order(order_id):
    """Мәртебені (мыс. 'received') өзгерту — trg_order_received триггерін іске қосады."""
    data = request.get_json()
    execute("UPDATE orders SET status=%s WHERE order_id=%s",
            (data["status"], order_id))
    return jsonify({"status": "ok"})


@app.route("/api/orders/<int:order_id>", methods=["DELETE"])
def delete_order(order_id):
    execute("DELETE FROM orders WHERE order_id=%s", (order_id,))
    return jsonify({"status": "deleted"})


# ========================================================================
# 6. /api/movements — соңғы 50 қалдық қозғалысы
# ========================================================================
@app.route("/api/movements", methods=["GET"])
def get_movements():
    rows = query(
        """SELECT sm.movement_id, sm.moved_at, m.material_name,
                  w.warehouse_name, sm.move_type, sm.quantity, sm.notes
           FROM stock_movements sm
           JOIN materials m ON m.material_id = sm.material_id
           JOIN warehouses w ON w.warehouse_id = sm.warehouse_id
           ORDER BY sm.moved_at DESC
           LIMIT 50""")
    return jsonify(rows)


# ========================================================================
# 7. /api/alerts — ескертулерді тізімдеу және шешу
# ========================================================================
@app.route("/api/alerts", methods=["GET"])
def get_alerts():
    rows = query(
        """SELECT a.*, m.material_name, o.order_number
           FROM alerts a
           LEFT JOIN materials m ON m.material_id = a.material_id
           LEFT JOIN orders o ON o.order_id = a.order_id
           WHERE a.is_resolved = FALSE
           ORDER BY a.created_at DESC""")
    return jsonify(rows)


@app.route("/api/alerts/<int:alert_id>/resolve", methods=["PUT"])
def resolve_alert(alert_id):
    execute("UPDATE alerts SET is_resolved = TRUE WHERE alert_id=%s", (alert_id,))
    return jsonify({"status": "resolved"})


# ------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(debug=True, port=5000)
