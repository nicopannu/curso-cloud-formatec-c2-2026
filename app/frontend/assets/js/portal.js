// Portal de clientes - CloudCuyo Legacy
const API_BASE = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
  ? 'http://192.168.56.10/api'
  : '/api';

let currentSession = null;

// Login form handler
document.getElementById('login-form')?.addEventListener('submit', async (e) => {
  e.preventDefault();

  const customerCode = document.getElementById('customer_code').value.trim();
  const email = document.getElementById('email').value.trim();

  if (!customerCode || !email) {
    showError('Por favor complete todos los campos');
    return;
  }

  try {
    const response = await fetch(`${API_BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ customer_code: customerCode, email: email })
    });

    if (!response.ok) {
      const error = await response.json();
      showError(error.error || 'Credenciales invalidas');
      return;
    }

    const data = await response.json();
    currentSession = data;

    // Store session in sessionStorage
    sessionStorage.setItem('cloudcuyo_session', JSON.stringify(data));

    // Load dashboard
    await loadDashboard();

  } catch (err) {
    showError('Error de conexion: ' + err.message);
  }
});

// Logout handler
document.getElementById('logout-btn')?.addEventListener('click', () => {
  currentSession = null;
  sessionStorage.removeItem('cloudcuyo_session');
  showLogin();
});

// Show error message
function showError(message) {
  const errorDiv = document.getElementById('login-error');
  errorDiv.textContent = message;
  errorDiv.style.display = 'block';
  setTimeout(() => {
    errorDiv.style.display = 'none';
  }, 5000);
}

// Show login section
function showLogin() {
  document.getElementById('login-section').style.display = 'grid';
  document.getElementById('dashboard-section').style.display = 'none';
  document.getElementById('customer_code').value = '';
  document.getElementById('email').value = '';
}

// Load dashboard with customer data
async function loadDashboard() {
  document.getElementById('login-section').style.display = 'none';
  document.getElementById('dashboard-section').style.display = 'grid';

  // Display customer info
  const customer = currentSession.customer;
  document.getElementById('customer-name').textContent = customer.contact_name;
  document.getElementById('company-name').textContent = customer.company_name;
  document.getElementById('customer-code-display').textContent = customer.customer_code;
  document.getElementById('customer-email').textContent = customer.email;
  document.getElementById('contract-start').textContent = formatDate(customer.contract_start_date);
  document.getElementById('total-spent').textContent = customer.total_spent.toLocaleString('es-AR', { minimumFractionDigits: 2 });

  // Load services
  await loadServices(customer.customer_code);

  // Load payments
  await loadPayments(customer.customer_code);
}

// Load customer services
async function loadServices(customerCode) {
  try {
    const response = await fetch(`${API_BASE}/customers/${customerCode}/services`);
    const services = await response.json();

    const container = document.getElementById('services-list');

    if (services.length === 0) {
      container.innerHTML = '<p>No hay servicios contratados.</p>';
      return;
    }

    let html = '<table style="width: 100%; border-collapse: collapse;">';
    html += '<tr style="background: #ddd; font-weight: bold;">';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: left;">Servicio</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: left;">Fecha Contrato</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: right;">Costo Mensual</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: center;">Estado</th>';
    html += '</tr>';

    services.forEach(service => {
      html += '<tr>';
      html += `<td style="padding: 8px; border: 1px solid #ccc;">${service.service_name}</td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc;">${formatDate(service.contracted_date)}</td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc; text-align: right;">$${service.monthly_cost.toLocaleString('es-AR', { minimumFractionDigits: 2 })}</td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc; text-align: center;"><span style="color: ${service.status === 'active' ? 'green' : 'red'}; font-weight: bold;">${service.status.toUpperCase()}</span></td>`;
      html += '</tr>';
    });

    html += '</table>';
    container.innerHTML = html;

  } catch (err) {
    document.getElementById('services-list').innerHTML = '<p style="color: red;">Error cargando servicios: ' + err.message + '</p>';
  }
}

// Load customer payments
async function loadPayments(customerCode) {
  try {
    const response = await fetch(`${API_BASE}/customers/${customerCode}/payments`);
    const payments = await response.json();

    const container = document.getElementById('payments-list');

    if (payments.length === 0) {
      container.innerHTML = '<p>No hay pagos registrados.</p>';
      return;
    }

    let html = '<table style="width: 100%; border-collapse: collapse;">';
    html += '<tr style="background: #ddd; font-weight: bold;">';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: left;">Fecha</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: right;">Monto</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: left;">Metodo</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: center;">Estado</th>';
    html += '<th style="padding: 8px; border: 1px solid #999; text-align: left;">Notas</th>';
    html += '</tr>';

    payments.forEach(payment => {
      html += '<tr>';
      html += `<td style="padding: 8px; border: 1px solid #ccc;">${formatDate(payment.payment_date)}</td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc; text-align: right;">$${payment.amount.toLocaleString('es-AR', { minimumFractionDigits: 2 })}</td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc;">${payment.payment_method}</td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc; text-align: center;"><span style="color: ${payment.status === 'completed' ? 'green' : 'orange'}; font-weight: bold;">${payment.status.toUpperCase()}</span></td>`;
      html += `<td style="padding: 8px; border: 1px solid #ccc; font-size: 11px;">${payment.notes || '-'}</td>`;
      html += '</tr>';
    });

    html += '</table>';
    container.innerHTML = html;

  } catch (err) {
    document.getElementById('payments-list').innerHTML = '<p style="color: red;">Error cargando pagos: ' + err.message + '</p>';
  }
}

// Format date helper
function formatDate(dateStr) {
  const date = new Date(dateStr);
  return date.toLocaleDateString('es-AR', { year: 'numeric', month: '2-digit', day: '2-digit' });
}

// Check for existing session on page load
window.addEventListener('DOMContentLoaded', () => {
  const savedSession = sessionStorage.getItem('cloudcuyo_session');
  if (savedSession) {
    try {
      currentSession = JSON.parse(savedSession);
      loadDashboard();
    } catch (err) {
      showLogin();
    }
  } else {
    showLogin();
  }
});
