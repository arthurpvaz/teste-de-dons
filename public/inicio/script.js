import { supabase } from '../supabase-client.js';
/* ==========================================================================
   1. ESTADO GLOBAL DA APLICAÇÃO
   ========================================================================== */

console.log('SCRIPT.JS CARREGOU!');

let membersData = [];
let selectedMemberId = null;
let currentChurch = localStorage.getItem('igrejaSelecionada') || 'IPB Sapucaia do Sul';
let currentFilterKey = 'todos';
let currentFilterTitle = 'Todos os Membros';
let suggestedMinistry = null;
let donsAtuaisModal = []; // Array temporário para manipular os dons no modal

let requisicaoEmAndamento = false;
let churchesCache = [];
let ministriesCache = [];
let supabaseReady = false;

/* ==========================================================================
   2. BUSCA DE DADOS DA API (MongoDB / Node.js)
   ========================================================================== */

async function fetchMembers() {
  if (requisicaoEmAndamento) return;
  requisicaoEmAndamento = true;

  try {
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData.session) {
      window.location.href = '../login/login.html';
      return;
    }

    const church = churchesCache.find(c => c.name === currentChurch);
    const churchId = currentChurch !== 'Geral Presbiterial' ? church?.id : null;

    let membersQuery = supabase
      .from('members')
      .select('id, church_id, full_name, email, phone, bond, status, archived, archived_reason, created_at')
      .eq('archived', false)
      .order('full_name');

    if (churchId) membersQuery = membersQuery.eq('church_id', churchId);

    const [membersRes, giftsRes, assignmentsRes, ministriesRes, notesRes, visitsRes] = await Promise.all([
      membersQuery,
      supabase.from('member_gift_scores').select('member_id, gift_id, score, gifts(code,name,sort_order)'),
      churchId
        ? supabase.from('ministry_assignments').select('id, member_id, ministry_id, role, active').eq('church_id', churchId).eq('active', true)
        : supabase.from('ministry_assignments').select('id, member_id, ministry_id, role, active').eq('active', true),
      churchId
        ? supabase.from('ministries').select('id, church_id, name, description, active').eq('church_id', churchId).eq('active', true).order('name')
        : supabase.from('ministries').select('id, church_id, name, description, active').eq('active', true).order('name'),
      churchId
        ? supabase.from('pastoral_notes').select('id, member_id, church_id, body, created_at').eq('church_id', churchId).order('created_at', { ascending: false })
        : supabase.from('pastoral_notes').select('id, member_id, church_id, body, created_at').order('created_at', { ascending: false }),
      churchId
        ? supabase.from('pastoral_visits').select('id, member_id, church_id, scheduled_at, done, outcome, created_at').eq('church_id', churchId).order('created_at', { ascending: false })
        : supabase.from('pastoral_visits').select('id, member_id, church_id, scheduled_at, done, outcome, created_at').order('created_at', { ascending: false })
    ]);

    const responses = [membersRes, giftsRes, assignmentsRes, ministriesRes, notesRes, visitsRes];
    const firstError = responses.find(r => r.error)?.error;
    if (firstError) throw firstError;

    const giftsByMember = {};
    (giftsRes.data || []).forEach(row => {
      if (!giftsByMember[row.member_id]) giftsByMember[row.member_id] = [];
      if (Number(row.score) > 0 && row.gifts?.name) giftsByMember[row.member_id].push(row.gifts.name);
    });

    const ministryById = Object.fromEntries((ministriesRes.data || []).map(m => [m.id, m]));
    const ministriesByMember = {};
    (assignmentsRes.data || []).forEach(a => {
      if (!ministriesByMember[a.member_id]) ministriesByMember[a.member_id] = [];
      const ministry = ministryById[a.ministry_id];
      if (ministry) ministriesByMember[a.member_id].push(ministry.name);
    });

    const historyByMember = {};
    const pushHistory = (memberId, entry) => {
      if (!historyByMember[memberId]) historyByMember[memberId] = [];
      historyByMember[memberId].push(entry);
    };
    (notesRes.data || []).forEach(n => pushHistory(n.member_id, {
      date: new Date(n.created_at).toLocaleDateString('pt-BR'),
      category: 'Aconselhamento',
      text: n.body
    }));
    (visitsRes.data || []).forEach(v => pushHistory(v.member_id, {
      date: new Date(v.scheduled_at || v.created_at).toLocaleDateString('pt-BR'),
      category: 'Visita Pastoral',
      text: v.outcome || (v.done ? 'Visita realizada.' : 'Visita agendada.')
    }));

    membersData = (membersRes.data || []).map(m => {
      const ministryNames = ministriesByMember[m.id] || [];
      const status = m.status === 'ativo' ? 'ok' : (m.status === 'em_alerta' ? 'warning' : 'danger');
      const statusText = m.status === 'ativo' ? (ministryNames.length ? 'Ativo e Engajado' : 'Aguardando Encaminhamento')
        : m.status === 'em_alerta' ? 'Em alerta pastoral' : 'Inativo / Desviado';
      return {
        id: m.id,
        _id: m.id,
        name: m.full_name,
        email: m.email,
        phone: m.phone,
        church: churchesCache.find(c => c.id === m.church_id)?.name || currentChurch,
        churchId: m.church_id,
        role: bondToLabel(m.bond),
        bond: m.bond,
        ministry: ministryNames.length ? ministryNames : ['Sem Ministério'],
        gifts: giftsByMember[m.id] || [],
        status,
        statusText,
        attendance: { culto: '-', ebd: '-', oracao: '-' },
        risks: m.status === 'em_alerta' ? ['Acompanhamento pastoral necessário'] : [],
        history: (historyByMember[m.id] || []).sort((a,b) => b.date.localeCompare(a.date)),
        reminder: { date: null, time: null, repeat: 'none' }
      };
    });

    ministriesCache = ministriesRes.data || [];
    updateBadges();
    renderFilteredList();
    renderGiftsPieChart();
  } catch (err) {
    console.error('Erro ao buscar dados do Supabase:', err);
    if (err?.message) alert(`Não foi possível carregar os dados: ${err.message}`);
  } finally {
    requisicaoEmAndamento = false;
  }
}

function bondToLabel(bond) {
  return ({
    comungante: 'Membro Comungante',
    nao_comungante: 'Membro Não-Comungante',
    visitante: 'Congregante / Visitante'
  })[bond] || 'Membro';
}

setInterval(fetchMembers, 30000);

function obterMembrosDaIgrejaAtual() {
  return membersData.filter(m => {
    if (!currentChurch || currentChurch === 'Geral Presbiterial') return true;
    return m.church === currentChurch;
  });
}

/* ==========================================================================
   3. NAVEGAÇÃO E REGRAS DE EXIBIÇÃO (IGREJAS E GRUPOS)
   ========================================================================== */

export function showDashboard(churchName = 'IPB Sapucaia do Sul') {
  currentChurch = churchName;
  localStorage.setItem('igrejaSelecionada', churchName);

  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = `Dashboard Pastoral - ${churchName}`;
  if (dashEl) dashEl.style.display = 'block';
  if (membersEl) membersEl.style.display = 'none';
  if (loginEl) loginEl.style.display = 'none';
  if (cadastroFielEl) cadastroFielEl.style.display = 'none';
  if (envioFormEl) envioFormEl.style.display = 'none';
  if (formularioDonsEl) formularioDonsEl.style.display = 'none';

  fetchMembers();
  updateBadges();

  requestAnimationFrame(() => {
    renderGiftsPieChart();
  });
}

export function selectChurchAndGroup(churchName, groupKey, titleText) {
  currentChurch = churchName;
  localStorage.setItem('igrejaSelecionada', churchName);
  
  currentFilterKey = groupKey;
  currentFilterTitle = titleText;

  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = titleText;
  if (dashEl) dashEl.style.display = 'none';
  if (membersEl) membersEl.style.display = 'block';
  if (loginEl) loginEl.style.display = 'none';
  if (cadastroFielEl) cadastroFielEl.style.display = 'none';
  if (envioFormEl) envioFormEl.style.display = 'none';
  if (formularioDonsEl) formularioDonsEl.style.display = 'none';

  fetchMembers();
}

export function showGroup(groupKey, titleText) {
  currentFilterKey = groupKey;
  currentFilterTitle = titleText;

  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = titleText;
  if (dashEl) dashEl.style.display = 'none';
  if (membersEl) membersEl.style.display = 'block';
  if (loginEl) loginEl.style.display = 'none';
  if (cadastroFielEl) cadastroFielEl.style.display = 'none';
  if (envioFormEl) envioFormEl.style.display = 'none';
  if (formularioDonsEl) formularioDonsEl.style.display = 'none';

  renderFilteredList();
}

export function showLoginView(titleText = 'Gestão de Permissões / Pastores') {
  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = titleText;
  if (dashEl) dashEl.style.display = 'none';
  if (membersEl) membersEl.style.display = 'none';
  if (cadastroFielEl) cadastroFielEl.style.display = 'none';
  if (envioFormEl) envioFormEl.style.display = 'none';
  if (formularioDonsEl) formularioDonsEl.style.display = 'none';
  
  if (loginEl) {
    loginEl.style.display = 'block';
    const iframe = loginEl.querySelector('iframe');
    if (iframe && !iframe.src.includes('login.html')) {
      iframe.src = '../login/login.html';
    }
  }
}

export function showCadastroMembrosView(titleText = 'Adicionar Novo Membro / Fiel') {
  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = titleText;
  if (dashEl) dashEl.style.display = 'none';
  if (membersEl) membersEl.style.display = 'none';
  if (loginEl) loginEl.style.display = 'none';
  if (envioFormEl) envioFormEl.style.display = 'none';
  if (formularioDonsEl) formularioDonsEl.style.display = 'none';

  if (cadastroFielEl) {
    cadastroFielEl.style.display = 'block';
    const iframe = cadastroFielEl.querySelector('iframe');
    if (iframe && !iframe.src.includes('fiel_Cadastro.html')) {
      iframe.src = '../fiel_Cadastro/fiel_Cadastro.html';
    }
  }
}

export function showEnvioFormularioView(titleText = 'Envio de Link - Formulário de Dons') {
  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = titleText;
  if (dashEl) dashEl.style.display = 'none';
  if (membersEl) membersEl.style.display = 'none';
  if (loginEl) loginEl.style.display = 'none';
  if (cadastroFielEl) cadastroFielEl.style.display = 'none';
  if (formularioDonsEl) formularioDonsEl.style.display = 'none';
  
  if (envioFormEl) {
    envioFormEl.style.display = 'block';
    const iframe = envioFormEl.querySelector('iframe');
    if (iframe && !iframe.src.includes('envio_Formulario.html')) {
      iframe.src = '../envio_Formulario/envio_Formulario.html';
    }
  }
}

export function showFormularioDonsView(titleText = 'Avaliação de Dons Espirituais - 133 Perguntas') {
  const titleEl = document.getElementById('view-title');
  const dashEl = document.getElementById('dashboard-view');
  const membersEl = document.getElementById('members-view');
  const loginEl = document.getElementById('login-view');
  const cadastroFielEl = document.getElementById('cadastro-fiel-view');
  const envioFormEl = document.getElementById('envio-formulario-view');
  const formularioDonsEl = document.getElementById('formulario-dons-view');

  if (titleEl) titleEl.innerText = titleText;
  if (dashEl) dashEl.style.display = 'none';
  if (membersEl) membersEl.style.display = 'none';
  if (loginEl) loginEl.style.display = 'none';
  if (cadastroFielEl) cadastroFielEl.style.display = 'none';
  if (envioFormEl) envioFormEl.style.display = 'none';
  
  if (formularioDonsEl) {
    formularioDonsEl.style.display = 'block';
    const iframe = formularioDonsEl.querySelector('iframe');
    if (iframe && !iframe.src.includes('formulario.html')) {
      iframe.src = '../Formulario__DONS/formulario.html';
    }
  }
}

export function carregarManutencaoFiel() {
  const loginView = document.getElementById('login-view');
  const titleEl = document.getElementById('view-title');

  if (titleEl) {
    titleEl.innerText = 'Pastores Cadastrados - Manutenção';
  }

  if (loginView) {
    const iframe = loginView.querySelector('iframe');
    if (iframe) {
      iframe.src = '../manutencao_Fiel/manutencao_Fiel.html';
    }
  }
}

export function toggleChurchDropdown() {
  const dropdown = document.getElementById('church-dropdown-list');
  const icon = document.getElementById('church-dropdown-icon');
  if (dropdown) {
    if (dropdown.style.display === 'none' || dropdown.style.display === '') {
      dropdown.style.display = 'block';
      if (icon) icon.textContent = '▲';
    } else {
      dropdown.style.display = 'none';
      if (icon) icon.textContent = '▼';
    }
  }
}

export function selecionarIgrejaSidebar(nomeIgreja) {
  currentChurch = nomeIgreja;
  localStorage.setItem('igrejaSelecionada', nomeIgreja);

  const label = document.getElementById('current-church-label');
  if (label) {
    label.textContent = `🏛️ ${nomeIgreja}`;
  }

  toggleChurchDropdown();
  showDashboard(nomeIgreja);
}

/* ==========================================================================
   4. FILTROS E LISTAGEM DE MEMBROS
   ========================================================================== */

export function renderFilteredList() {
  const searchInput = document.getElementById('search-member');
  const searchTerm = searchInput ? searchInput.value.trim().toLowerCase() : '';

  let filtered = obterMembrosDaIgrejaAtual();

  filtered = filtered.filter(m => {
    const nome = String(m.name || '').toLowerCase();
    return nome.includes(searchTerm);
  });

  if (currentFilterKey === 'ausentes') {
    filtered = filtered.filter(m => m.status === 'danger' || m.status === 'warning');
  } else if (currentFilterKey === 'sem_ministerio') {
    filtered = filtered.filter(m => {
      const ministerios = normalizarLista(m.ministry);
      return ministerios.length === 0 || ministerios.includes('Sem Ministério');
    });
  } else if (currentFilterKey !== 'todos') {
    filtered = filtered.filter(m => {
      const ministerios = normalizarLista(m.ministry);
      return ministerios.includes(currentFilterKey);
    });
  }

  renderMembers(filtered);
}

function normalizarLista(valor) {
  if (Array.isArray(valor)) {
    return valor.filter(item => typeof item === 'string');
  }
  if (typeof valor === 'string' && valor.trim() !== '') {
    return [valor];
  }
  return [];
}

function renderMembers(list) {
  const container = document.getElementById('members-container');
  if (!container) return;

  container.innerHTML = '';

  if (list.length === 0) {
    container.innerHTML = `<p style="color:var(--text-muted); padding:10px;">Nenhum membro encontrado para esta unidade.</p>`;
    return;
  }

  list.forEach(m => {
    const statusClass = m.status === 'danger' ? 'status-danger' : m.status === 'warning' ? 'status-warning' : 'status-ok';
    const ministries = normalizarLista(m.ministry);
    const vinculo = ministries.length > 0 && !ministries.includes('Sem Ministério') ? ministries.join(', ') : '👤 Sem Ministério';

    let reminderBadge = '';
    if (m.reminder && m.reminder.date) {
      const partes = String(m.reminder.date).split('-');
      if (partes.length === 3) {
        const horario = m.reminder.time || '--:--';
        reminderBadge = `<span class="todo-badge">🔔 ${partes[2]}/${partes[1]} às ${horario}</span>`;
      }
    }

    const giftsList = normalizarLista(m.gifts);
    const memberId = m._id || m.id;

    const item = document.createElement('li');
    item.className = 'member-item';
    item.dataset.id = memberId || '';

    const memberInfo = document.createElement('div');
    memberInfo.className = 'member-info';

    const avatar = document.createElement('div');
    avatar.className = 'avatar';
    avatar.textContent = m.name ? m.name[0] : 'M';

    const details = document.createElement('div');
    const name = document.createElement('strong');
    name.textContent = m.name || 'Nome não informado';

    const status = document.createElement('span');
    status.className = `status-badge ${statusClass}`;
    status.textContent = m.statusText || '';

    const reminder = document.createElement('span');
    reminder.innerHTML = reminderBadge;

    const ministryLine = document.createElement('div');
    ministryLine.style.color = 'var(--text-muted)';
    ministryLine.style.fontSize = '0.85rem';
    ministryLine.appendChild(document.createTextNode('Ministério(s): '));

    const ministryStrong = document.createElement('strong');
    ministryStrong.textContent = vinculo;
    ministryLine.appendChild(ministryStrong);

    details.append(name, document.createElement('br'), status);
    if (reminderBadge) details.appendChild(reminder);
    details.appendChild(document.createElement('br'));
    details.appendChild(ministryLine);

    memberInfo.append(avatar, details);

    const giftsContainer = document.createElement('div');
    giftsList.forEach(gift => {
      const tag = document.createElement('span');
      tag.className = 'gift-tag';
      tag.textContent = gift;
      giftsContainer.appendChild(tag);
    });

    item.append(memberInfo, giftsContainer);
    item.addEventListener('click', () => {
      if (memberId) openProfileModal(memberId);
    });

    container.appendChild(item);
  });
}

/* ==========================================================================
   5. GRÁFICO DE PIZZA: MAPEAMENTO DE DONS
   ========================================================================== */

export function renderGiftsPieChart() {
  const canvas = document.getElementById('giftsPieChart');
  const legendContainer = document.getElementById('gifts-legend');

  if (!canvas || !legendContainer) return;

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const counts = {};
  const membrosDaIgreja = obterMembrosDaIgrejaAtual();

  membrosDaIgreja.forEach(membro => {
    const dons = normalizarLista(membro.gifts);
    dons.forEach(dom => {
      const nomeDom = dom.trim();
      if (nomeDom !== '') {
        counts[nomeDom] = (counts[nomeDom] || 0) + 1;
      }
    });
  });

  const giftColors = {
    'Ensino': '#0284c7',
    'Serviço': '#00563B',
    'Liderança': '#166534',
    'Misericórdia': '#b45309',
    'Música': '#7c3aed',
    'Hospitalidade': '#0d9488',
    'Diaconia': '#dc2626'
  };

  const items = Object.entries(counts)
    .map(([label, value]) => ({ label, value, color: giftColors[label] || '#64748b' }))
    .sort((a, b) => b.value - a.value);

  const rect = canvas.getBoundingClientRect();
  const largura = rect.width || canvas.clientWidth || 260;
  const altura = rect.height || canvas.clientHeight || 260;
  const escala = Math.max(1, window.devicePixelRatio || 1);

  canvas.width = Math.round(largura * escala);
  canvas.height = Math.round(altura * escala);

  ctx.setTransform(escala, 0, 0, escala, 0, 0);
  ctx.clearRect(0, 0, largura, altura);
  legendContainer.innerHTML = '';

  const total = items.reduce((soma, item) => soma + item.value, 0);

  if (total === 0) {
    const centroX = largura / 2;
    const centroY = altura / 2;
    const raio = Math.max(5, Math.min(largura, altura) / 2 - 10);

    ctx.beginPath();
    ctx.arc(centroX, centroY, raio, 0, Math.PI * 2);
    ctx.fillStyle = '#e2e8f0';
    ctx.fill();

    ctx.fillStyle = '#64748b';
    ctx.font = '13px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('Sem dons cadastrados', centroX, centroY);

    const mensagem = document.createElement('p');
    mensagem.style.fontSize = '0.82rem';
    mensagem.style.color = 'var(--text-muted)';
    mensagem.style.fontStyle = 'italic';
    mensagem.textContent = 'Nenhum dom cadastrado no momento nesta igreja.';
    legendContainer.appendChild(mensagem);
    return;
  }

  const centerX = largura / 2;
  const centerY = altura / 2;
  const radius = Math.max(5, Math.min(largura, altura) / 2 - 10);
  let startAngle = -Math.PI / 2;

  items.forEach(item => {
    const sliceAngle = (item.value / total) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(centerX, centerY);
    ctx.arc(centerX, centerY, radius, startAngle, startAngle + sliceAngle);
    ctx.closePath();
    ctx.fillStyle = item.color;
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#ffffff';
    ctx.stroke();
    startAngle += sliceAngle;
  });

  items.forEach(item => {
    const percentual = ((item.value / total) * 100).toFixed(1);
    const linha = document.createElement('div');
    linha.className = 'legend-item';

    const marcador = document.createElement('span');
    marcador.className = 'legend-color';
    marcador.style.backgroundColor = item.color;

    const texto = document.createElement('span');
    texto.className = 'legend-text';
    const nome = document.createElement('strong');
    nome.textContent = `${item.label}:`;

    texto.append(nome, document.createTextNode(` ${item.value} pess. (${percentual}%)`));
    linha.append(marcador, texto);
    legendContainer.appendChild(linha);
  });
}

/* ==========================================================================
   6. GESTÃO DE DONS NO MODAL
   ========================================================================== */

export function renderizarDonsModal() {
  const giftsContainer = document.getElementById('modal-gifts');
  if (!giftsContainer) return;
  
  giftsContainer.innerHTML = '';

  if (donsAtuaisModal.length === 0) {
    giftsContainer.innerHTML = '<span style="font-size:0.8rem; color:#64748b;">Nenhum dom mapeado.</span>';
    return;
  }

  donsAtuaisModal.forEach((gift, index) => {
    const tag = document.createElement('span');
    tag.className = 'gift-tag';
    tag.style.display = 'inline-flex';
    tag.style.alignItems = 'center';
    tag.style.gap = '5px';
    tag.style.fontSize = '0.85rem';
    tag.style.padding = '4px 10px';
    tag.innerHTML = `${gift} <span onclick="removerDomModal(${index})" style="cursor: pointer; font-weight: bold; color: #dc2626; margin-left: 3px;" title="Remover dom">&times;</span>`;
    giftsContainer.appendChild(tag);
  });
}

export function adicionarDomModal() {
  const select = document.getElementById('select-novo-dom');
  if (!select) return;
  
  const novoDom = select.value;
  if (!novoDom) {
    alert('Selecione um dom para adicionar.');
    return;
  }

  if (donsAtuaisModal.includes(novoDom)) {
    alert('Este membro já possui este dom mapeado.');
    return;
  }

  donsAtuaisModal.push(novoDom);
  renderizarDonsModal();
  select.value = '';
}

export function removerDomModal(index) {
  donsAtuaisModal.splice(index, 1);
  renderizarDonsModal();
}

/* ==========================================================================
   7. GERENCIAMENTO DE PERFIL E MODAL
   ========================================================================== */

export function openProfileModal(id) {
  selectedMemberId = id;
  const m = membersData.find(item => String(item._id || item.id) === String(id));
  if (!m) return;

  const setText = (elementId, value) => {
    const el = document.getElementById(elementId);
    if (el) el.textContent = value;
  };

  setText('modal-name', m.name || 'Nome não informado');
  setText('modal-role', m.role || 'Membro Comungante');
  setText('modal-avatar', m.name ? m.name[0] : 'M');

  const currentMinistry = normalizarLista(m.ministry);
  const selectMinistry = document.getElementById('modal-select-ministry');
  if (selectMinistry) selectMinistry.value = currentMinistry[0] || 'Sem Ministério';

  const statusClass = m.status === 'danger' ? 'status-danger' : m.status === 'warning' ? 'status-warning' : 'status-ok';
  const statusBadge = document.getElementById('modal-status-badge');

  if (statusBadge) {
    statusBadge.innerHTML = '';
    const badge = document.createElement('span');
    badge.className = `status-badge ${statusClass}`;
    badge.textContent = m.statusText || '';
    statusBadge.appendChild(badge);
  }

  setText('att-culto', m.attendance?.culto || '-');
  setText('att-ebd', m.attendance?.ebd || '-');
  setText('att-oracao', m.attendance?.oracao || '-');

  donsAtuaisModal = Array.isArray(m.gifts) ? [...m.gifts] : [];
  renderizarDonsModal();

  const risksList = normalizarLista(m.risks);
  const risksContainer = document.getElementById('modal-risks');
  if (risksContainer) {
    risksContainer.innerHTML = '';
    risksList.forEach(risk => {
      const li = document.createElement('li');
      li.textContent = risk;
      risksContainer.appendChild(li);
    });
  }

  suggestedMinistry = calculateMinistryMatch(donsAtuaisModal);
  const matchBox = document.getElementById('match-suggestion');
  const isSemMin = currentMinistry.length === 0 || currentMinistry.includes('Sem Ministério');

  if (matchBox) {
    if (suggestedMinistry && isSemMin) {
      setText('match-ministry-name', suggestedMinistry);
      matchBox.style.display = 'flex';
    } else {
      matchBox.style.display = 'none';
    }
  }

  renderTimeline(normalizarLista(m.history).length ? m.history : []);

  const todoCheck = document.getElementById('todo-enable');
  if (todoCheck) {
    const temLembrete = Boolean(m.reminder?.date);
    todoCheck.checked = temLembrete;
    toggleTodoFields();

    const dateInput = document.getElementById('todo-date');
    const timeInput = document.getElementById('todo-time');
    const repeatInput = document.getElementById('todo-repeat');

    if (dateInput) dateInput.value = m.reminder?.date || '';
    if (timeInput) timeInput.value = m.reminder?.time || '';
    if (repeatInput) repeatInput.value = m.reminder?.repeat || 'none';
  }

  const modal = document.getElementById('profile-modal');
  if (modal) modal.classList.add('active');
}

function calculateMinistryMatch(gifts) {
  if (gifts.includes('Ensino') || gifts.includes('Liderança')) return 'EBD';
  if (gifts.includes('Música')) return 'Louvor';
  if (gifts.includes('Serviço') || gifts.includes('Diaconia')) return 'Diaconia';
  if (gifts.includes('Hospitalidade') || gifts.includes('Misericórdia')) return 'Recepção';
  return null;
}

export function applyMatch() {
  if (!suggestedMinistry) return;
  const select = document.getElementById('modal-select-ministry');
  const matchBox = document.getElementById('match-suggestion');

  if (select) select.value = suggestedMinistry;
  if (matchBox) matchBox.style.display = 'none';
}

export async function saveMemberProfile() {
  const select = document.getElementById('modal-select-ministry');
  if (!select) return;

  const selectedMinistry = select.value;
  const member = membersData.find(m => String(m._id || m.id) === String(selectedMemberId));
  if (!member) return;

  try {
    const { error: memberError } = await supabase
      .from('members')
      .update({ status: selectedMinistry === 'Sem Ministério' ? 'em_alerta' : 'ativo' })
      .eq('id', member.id);
    if (memberError) throw memberError;

    await supabase.from('ministry_assignments').update({ active: false }).eq('member_id', member.id);

    if (selectedMinistry !== 'Sem Ministério') {
      const ministry = ministriesCache.find(m => m.name === selectedMinistry && m.church_id === member.churchId);
      if (!ministry) throw new Error(`O ministério "${selectedMinistry}" não existe nesta igreja.`);
      const { error } = await supabase.from('ministry_assignments').upsert({
        ministry_id: ministry.id,
        member_id: member.id,
        church_id: member.churchId,
        active: true
      }, { onConflict: 'ministry_id,member_id' });
      if (error) throw error;
    }

    closeModal();
    await fetchMembers();
    alert('Perfil atualizado com sucesso!');
  } catch (err) {
    console.error('Erro ao atualizar perfil:', err);
    alert(`Não foi possível salvar o perfil: ${err.message || 'erro desconhecido'}`);
  }
}

/* ==========================================================================
   8. HISTÓRICO E TIMELINE
   ========================================================================== */

function renderTimeline(historyList) {
  const container = document.getElementById('modal-timeline');
  if (!container) return;

  container.innerHTML = '';
  if (!Array.isArray(historyList) || historyList.length === 0) {
    container.innerHTML = `<p style="font-size:0.8rem; color:var(--text-muted);">Nenhum histórico registrado.</p>`;
    return;
  }

  historyList.forEach(h => {
    const item = document.createElement('div');
    item.className = 'timeline-item';

    const date = document.createElement('span');
    date.className = 'timeline-date';
    date.textContent = h.date || '';

    const category = document.createElement('span');
    category.className = 'timeline-category';
    category.textContent = h.category || '';

    const text = document.createElement('div');
    text.className = 'timeline-text';
    text.textContent = h.text || '';

    item.append(date, category, text);
    container.appendChild(item);
  });
}

export async function addHistoryEntry() {
  const textInput = document.getElementById('new-history-text');
  const categoryInput = document.getElementById('new-history-category');
  const text = textInput ? textInput.value.trim() : '';
  const category = categoryInput ? categoryInput.value : '';
  if (!text) return alert('Digite o texto do histórico.');

  const member = membersData.find(m => String(m._id || m.id) === String(selectedMemberId));
  if (!member) return;

  try {
    const body = `[${category}] ${text}`;
    const { error } = await supabase.from('pastoral_notes').insert({
      member_id: member.id,
      church_id: member.churchId,
      body
    });
    if (error) throw error;

    if (textInput) textInput.value = '';
    await fetchMembers();
    const updated = membersData.find(m => String(m.id) === String(member.id));
    renderTimeline(updated?.history || []);
  } catch (err) {
    console.error('Erro ao adicionar histórico:', err);
    alert(`Não foi possível salvar o histórico: ${err.message || 'erro desconhecido'}`);
  }
}

/* ==========================================================================
   9. INDICADORES E BADGES DO DASHBOARD
   ========================================================================== */

function updateBadges() {
  const membrosDaIgreja = obterMembrosDaIgrejaAtual();

  const countSemMin = membrosDaIgreja.filter(m => {
    const ministerios = normalizarLista(m.ministry);
    return ministerios.length === 0 || ministerios.includes('Sem Ministério');
  }).length;

  const countAusentes = membrosDaIgreja.filter(m => m.status === 'danger' || m.status === 'warning').length;

  const setInner = (id, valor) => {
    const el = document.getElementById(id);
    if (el) el.textContent = valor;
  };

  setInner('badge-sem-min', countSemMin);
  setInner('dash-sem-min-count', countSemMin);
  setInner('badge-ausentes', countAusentes);
  setInner('dash-ausentes-count', countAusentes);
  setInner('dash-total-members', membrosDaIgreja.length);
}

/* ==========================================================================
   10. LEMBRETES E CONTROLES DOS MODAIS
   ========================================================================== */

export function toggleTodoFields() {
  const checkbox = document.getElementById('todo-enable');
  const fields = document.getElementById('todo-fields');
  const actions = document.getElementById('todo-actions-bar');

  if (!checkbox) return;
  const display = checkbox.checked ? 'flex' : 'none';

  if (fields) fields.style.display = display;
  if (actions) actions.style.display = display;
}

export function closeModal() {
  const modal = document.getElementById('profile-modal');
  if (modal) modal.classList.remove('active');
}

export function openNewChurchModal() {
  const modal = document.getElementById('new-church-modal');
  if (modal) modal.classList.add('active');
}

export function closeNewChurchModal() {
  const modal = document.getElementById('new-church-modal');
  if (modal) modal.classList.remove('active');
}

/* ==========================================================================
   11. EXPORTAÇÃO CSV
   ========================================================================== */

export function exportToCSV() {
  let csv = 'Nome,Telefone,Vínculo,Ministério,Status,Dons\n';
  const escaparCSV = valor => `"${String(valor ?? '').replace(/"/g, '""')}"`;
  const membrosDaIgreja = obterMembrosDaIgrejaAtual();

  membrosDaIgreja.forEach(m => {
    const ministerios = normalizarLista(m.ministry).join('; ');
    const dons = normalizarLista(m.gifts).join('; ');

    csv += [
      escaparCSV(m.name),
      escaparCSV(m.phone),
      escaparCSV(m.role),
      escaparCSV(ministerios),
      escaparCSV(m.statusText),
      escaparCSV(dons)
    ].join(',') + '\n';
  });

  const blob = new Blob(['\uFEFF', csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');

  link.href = url;
  link.download = 'relatorio_membros_ipb.csv';
  link.click();
  URL.revokeObjectURL(url);
}

/* ==========================================================================
   12. VÍNCULOS COM O ESCOPO GLOBAL (WINDOW)
   ========================================================================== */

Object.assign(window, {
  showDashboard,
  selectChurchAndGroup,
  showGroup,
  showLoginView,
  showCadastroMembrosView,
  showEnvioFormularioView,
  showFormularioDonsView,
  carregarManutencaoFiel,
  toggleChurchDropdown,
  selecionarIgrejaSidebar,
  renderFilteredList,
  renderGiftsPieChart,
  openProfileModal,
  applyMatch,
  addHistoryEntry,
  saveMemberProfile,
  toggleTodoFields,
  closeModal,
  openNewChurchModal,
  closeNewChurchModal,
  exportToCSV,
  adicionarDomModal,
  removerDomModal,
  handleCreateChurch
});

/* ==========================================================================
   13. INICIALIZAÇÃO DA APLICAÇÃO E CARREGAMENTO DE IGREJAS
   ========================================================================== */

document.addEventListener('DOMContentLoaded', async () => {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData.session) {
    window.location.href = '../login/login.html';
    return;
  }

  const searchInput = document.getElementById('search-member');
  if (searchInput) {
    searchInput.addEventListener('input', renderFilteredList);
  }

  await carregarIgrejasDoBanco();
  await fetchMembers();

  const igrejaSalva = localStorage.getItem('igrejaSelecionada') || 'IPB Sapucaia do Sul';
  currentChurch = igrejaSalva;
  showDashboard(igrejaSalva);

  window.addEventListener('resize', () => {
    requestAnimationFrame(renderGiftsPieChart);
  });
});

/* ==========================================================================
   14. ÁREA RESTRITA
   ========================================================================== */

const botao_Area_Restrita = document.getElementById('administrador');
if (botao_Area_Restrita) {
  botao_Area_Restrita.addEventListener('click', acessar_Area_Restrita);
}

function acessar_Area_Restrita(){
   window.location.href = '../administrador_Login/administrador_Login.html';
}

/* ==========================================================================
   15. GERENCIAMENTO DE IGREJAS NO MONGODB
   ========================================================================== */

export async function handleCreateChurch(event) {
  event.preventDefault();
  const nameInput = document.getElementById('church-name');
  const cityInput = document.getElementById('church-city');
  const churchName = nameInput.value.trim();
  const churchCity = cityInput.value.trim();
  if (!churchName) return;

  try {
    const slug = churchName.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    const { error } = await supabase.rpc('create_church', {
      p_name: churchName,
      p_slug: slug,
      p_city: churchCity
    });
    if (error) throw error;
    alert('Igreja cadastrada com sucesso no Supabase!');
    closeNewChurchModal();
    nameInput.value = '';
    cityInput.value = '';
    await carregarIgrejasDoBanco();
    const fullName = churchCity ? `${churchName} - ${churchCity}` : churchName;
    selecionarIgrejaSidebar(churchName);
  } catch (err) {
    console.error('Erro ao criar igreja:', err);
    alert(`Erro ao criar igreja: ${err.message || 'erro desconhecido'}`);
  }
}

async function carregarIgrejasDoBanco() {
  const container = document.getElementById('churches-list-container');
  if (!container) return;

  try {
    const { data, error } = await supabase.rpc('my_churches');
    if (error) throw error;
    churchesCache = data || [];

    const listaParaExibir = churchesCache.length ? churchesCache : [];
    const igrejaAtualSalva = localStorage.getItem('igrejaSelecionada') || (listaParaExibir[0]?.name || 'Geral Presbiterial');
    currentChurch = igrejaAtualSalva;

    const churchHtml = `
      <div class="church-selector-wrapper" style="position: relative; margin-bottom: 15px;">
        <div class="church-header" onclick="toggleChurchDropdown()" style="background: #ffffff; border: 1px solid #cbd5e1; padding: 10px 12px; border-radius: 6px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; font-weight: 600; color: var(--primary);">
          <span id="current-church-label">🏛️ ${igrejaAtualSalva}</span><span id="church-dropdown-icon">▼</span>
        </div>
        <div id="church-dropdown-list" style="display:none; position:absolute; top:100%; left:0; width:100%; background:white; border:1px solid #cbd5e1; border-radius:6px; box-shadow:0 4px 12px rgba(0,0,0,.1); z-index:100; margin-top:4px; max-height:200px; overflow-y:auto;">
          ${listaParaExibir.map(i => `<div onclick="selecionarIgrejaSidebar('${String(i.name).replace(/'/g, "\\'")}')" style="padding:10px 12px; cursor:pointer; font-size:.9rem; border-bottom:1px solid #f1f5f9;">🏛️ ${i.name}</div>`).join('')}
        </div>
      </div>
      <div class="sidebar-section">
        <div class="sidebar-title">Gestão de Pessoas</div>
        <ul class="nav-list">
          <li class="nav-item" onclick="showLoginView('Gestão de Permissões / Pastores')"><span>👤 Gestão de Permissões / Pastores</span></li>
          <li class="nav-item" onclick="showCadastroMembrosView('Adicionar Novo Membro / Fiel')"><span>➕ Adicionar Membros</span></li>
          <li class="nav-item" onclick="selectChurchAndGroup(document.getElementById('current-church-label').textContent.replace('🏛️','').trim(),'todos',document.getElementById('current-church-label').textContent.replace('🏛️','').trim()+' - Todos os Membros')"><span>👥 Consultar Membros</span></li>
          <li class="nav-item" onclick="showEnvioFormularioView('Envio de Link - Formulário de Dons')"><span>🔗 Link Formulário - Dons</span></li>
          <li class="nav-item" onclick="selectChurchAndGroup(document.getElementById('current-church-label').textContent.replace('🏛️','').trim(),'sem_ministerio',document.getElementById('current-church-label').textContent.replace('🏛️','').trim()+' - Sem Ministério')"><span>👤 Sem Ministério</span></li>
          <li class="nav-item" onclick="selectChurchAndGroup(document.getElementById('current-church-label').textContent.replace('🏛️','').trim(),'ausentes',document.getElementById('current-church-label').textContent.replace('🏛️','').trim()+' - Alertas de Ausência')"><span>⚠️ Alerta de Ausência</span></li>
          <li class="nav-item" id="sair"><span>🚪 Sair</span></li>
        </ul>
      </div>`;
    container.innerHTML = churchHtml;

    document.getElementById('sair')?.addEventListener('click', async () => {
      if (confirm('Deseja realmente sair?')) {
        await supabase.auth.signOut();
        window.location.href = '/';
      }
    });
  } catch (err) {
    console.error('Erro ao carregar igrejas do Supabase:', err);
    alert(`Não foi possível carregar as igrejas: ${err.message || 'erro desconhecido'}`);
  }
}
