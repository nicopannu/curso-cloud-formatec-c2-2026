async function loadHealth() {
  const el = document.getElementById('health');
  if (!el) return;
  try {
    const response = await fetch('/api/health');
    const data = await response.json();
    el.textContent = `API OK - nodo: ${data.node} - base: ${data.database}`;
  } catch (error) {
    el.textContent = 'No se pudo consultar la API. Revisar api01 o el proxy.';
  }
}

async function loadSolutions() {
  const el = document.getElementById('solutions');
  if (!el) return;
  try {
    const response = await fetch('/api/solutions');
    const data = await response.json();
    el.innerHTML = data.map(item => `
      <article class="solution-card">
        <h2>${item.name}</h2>
        <p>${item.description}</p>
        <strong>${item.strategy_hint}</strong>
      </article>
    `).join('');
  } catch (error) {
    el.textContent = 'No se pudieron cargar las soluciones.';
  }
}

function setupContactForm() {
  const form = document.getElementById('contactForm');
  const result = document.getElementById('formResult');
  if (!form || !result) return;

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const payload = Object.fromEntries(new FormData(form).entries());
    try {
      const response = await fetch('/api/contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await response.json();
      result.textContent = `Mensaje registrado con ID ${data.id}. Estrategia futura: refactor serverless.`;
      form.reset();
    } catch (error) {
      result.textContent = 'Error al enviar el mensaje. Revisar backend y base de datos.';
    }
  });
}

loadHealth();
loadSolutions();
setupContactForm();
