import { supabase } from '../supabase-client.js';

let questions = [];
let campuses = [];
let userAnswers = {};
let currentPage = 1;
const QUESTIONS_PER_PAGE = 10;
let TOTAL_PAGES = 1;

const OPTIONS = [
  { value: 0, text: '0 — Não me identifico' },
  { value: 1, text: '1 — Pouco me identifico' },
  { value: 2, text: '2 — Me identifico' },
  { value: 3, text: '3 — Muito me identifico' }
];

async function init() {
  try {
    const [{ data: questionData, error: questionError }, { data: campusData, error: campusError }] = await Promise.all([
      supabase.rpc('get_questionnaire_questions'),
      supabase.rpc('list_campuses')
    ]);
    if (questionError) throw questionError;
    if (campusError) throw campusError;
    questions = questionData || [];
    campuses = campusData || [];
    TOTAL_PAGES = Math.max(1, Math.ceil(questions.length / QUESTIONS_PER_PAGE));

    const select = document.getElementById('user-church');
    select.innerHTML = '<option value="">Selecione seu campus</option>';
    campuses.forEach(c => {
      const option = document.createElement('option');
      option.value = c.id;
      option.textContent = c.city ? `${c.name} — ${c.city}` : c.name;
      select.appendChild(option);
    });
    const campusSlug = new URLSearchParams(window.location.search).get('campus');
    if (campusSlug) {
      const preselected = campuses.find(c => c.slug === campusSlug);
      if (preselected) select.value = preselected.id;
    }

    document.getElementById('question-count').textContent = `${questions.length} Questões`;
    document.getElementById('page-indicator').textContent = `Página 1 de ${TOTAL_PAGES}`;
    document.getElementById('questions-range').textContent = questions.length ? `Perguntas 1 a ${Math.min(QUESTIONS_PER_PAGE, questions.length)}` : 'Nenhuma pergunta';
    renderPage(1);
  } catch (err) {
    console.error(err);
    showValidationAlert(`Não foi possível carregar o questionário: ${err.message || 'erro desconhecido'}`);
  }
}

function renderPage(page) {
  const wrapper = document.getElementById('questions-wrapper');
  wrapper.innerHTML = '';
  const start = (page - 1) * QUESTIONS_PER_PAGE;
  const pageQuestions = questions.slice(start, start + QUESTIONS_PER_PAGE);

  pageQuestions.forEach((q, idx) => {
    const globalIndex = start + idx + 1;
    const card = document.createElement('div');
    card.className = 'rounded-2xl shadow-sm border border-red-900/30 p-5';
    card.style.backgroundColor = '#04664d';
    card.style.color = '#fff';
    card.id = `q-card-${q.id}`;

    const options = OPTIONS.map((opt, optIdx) => {
      const optionId = `q_${q.id}_opt_${optIdx}`;
      const checked = Number(userAnswers[q.id]) === opt.value ? 'checked' : '';
      return `<div class="relative flex items-center">
        <input type="radio" id="${optionId}" name="q_${q.id}" value="${opt.value}" class="custom-radio sr-only" ${checked}>
        <label for="${optionId}" class="w-full flex items-center p-3 rounded-xl border border-white/20 cursor-pointer text-white text-xs sm:text-sm font-medium transition hover:bg-white/10">
          <span class="radio-indicator flex-shrink-0 w-4 h-4 rounded-full border-2 border-white/60 mr-3 flex items-center justify-center"></span>
          <span class="select-none">${opt.text}</span>
        </label>
      </div>`;
    }).join('');

    card.innerHTML = `<div class="flex items-start space-x-3 mb-3"><span class="bg-white/20 text-white font-bold text-xs px-2 py-1 rounded">#${globalIndex}</span><h3 class="text-sm sm:text-base font-semibold text-white">${escapeHtml(q.text)}</h3></div><div class="grid grid-cols-1 gap-2 pt-1">${options}</div>`;
    wrapper.appendChild(card);

    card.querySelectorAll(`input[name="q_${q.id}"]`).forEach(input => input.addEventListener('change', () => {
      userAnswers[q.id] = Number(input.value);
      card.classList.remove('border-yellow-300', 'ring-2', 'ring-yellow-300');
      hideValidationAlert();
    }));
  });
  updateNavigationUI();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function updateNavigationUI() {
  const start = (currentPage - 1) * QUESTIONS_PER_PAGE + 1;
  const end = Math.min(currentPage * QUESTIONS_PER_PAGE, questions.length);
  document.getElementById('progress-bar').style.width = `${(currentPage / TOTAL_PAGES) * 100}%`;
  document.getElementById('page-indicator').textContent = `Página ${currentPage} de ${TOTAL_PAGES}`;
  document.getElementById('questions-range').textContent = `Perguntas ${start} a ${end}`;
  document.getElementById('btn-prev').classList.toggle('hidden', currentPage === 1);
  document.getElementById('btn-next').classList.toggle('hidden', currentPage === TOTAL_PAGES);
  document.getElementById('btn-submit').classList.toggle('hidden', currentPage !== TOTAL_PAGES);
}

function validateCurrentPage() {
  const start = (currentPage - 1) * QUESTIONS_PER_PAGE;
  const pageQuestions = questions.slice(start, start + QUESTIONS_PER_PAGE);
  let firstUnanswered = null;
  pageQuestions.forEach(q => {
    const card = document.getElementById(`q-card-${q.id}`);
    if (userAnswers[q.id] === undefined) {
      firstUnanswered ??= q.id;
      card?.classList.add('border-yellow-300', 'ring-2', 'ring-yellow-300');
    } else card?.classList.remove('border-yellow-300', 'ring-2', 'ring-yellow-300');
  });
  if (firstUnanswered) {
    showValidationAlert('Responda todas as perguntas destacadas nesta página.');
    document.getElementById(`q-card-${firstUnanswered}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    return false;
  }
  return true;
}

window.goToNextPage = () => { if (validateCurrentPage() && currentPage < TOTAL_PAGES) { currentPage++; renderPage(currentPage); } };
window.goToPreviousPage = () => { if (currentPage > 1) { currentPage--; renderPage(currentPage); } };
window.hideValidationAlert = hideValidationAlert;

async function submitQuiz() {
  const name = document.getElementById('user-name').value.trim();
  const email = document.getElementById('user-email').value.trim();
  const phone = document.getElementById('user-phone').value.trim();
  const churchId = document.getElementById('user-church').value;
  const bond = document.getElementById('user-bond').value;
  const consent = document.getElementById('user-consent').checked;

  if (!name || !churchId || !bond || !consent) return showValidationAlert('Preencha nome, campus, vínculo e aceite de uso dos dados.');
  if (!validateCurrentPage()) return;

  const answers = questions.map(q => ({ question_id: q.id, value: Number(userAnswers[q.id]) }));
  const btn = document.getElementById('btn-submit'); btn.disabled = true; btn.textContent = 'Enviando...';
  try {
    const { data, error } = await supabase.rpc('submit_questionnaire', {
      p_church_id: churchId,
      p_name: name,
      p_email: email || null,
      p_phone: phone || null,
      p_bond: bond,
      p_consent: consent,
      p_answers: answers
    });
    if (error) throw error;
    displayResults(name, campuses.find(c => c.id === churchId)?.name || 'Campus', answers);
    alert('Formulário enviado com sucesso!');
  } catch (err) {
    console.error(err);
    showValidationAlert(`Não foi possível enviar o formulário: ${err.message || 'erro desconhecido'}`);
  } finally { btn.disabled = false; btn.innerHTML = 'Enviar Formulário <i class="fa-solid fa-check ml-1"></i>'; }
}
window.submitQuiz = submitQuiz;

function displayResults(name, churchName, answers) {
  const scores = {};
  questions.forEach(q => scores[q.gift_id] = (scores[q.gift_id] || 0) + Number(userAnswers[q.id] || 0));
  const gifts = [...new Map(questions.map(q => [q.gift_id, q.gift_name])).entries()].map(([id, gift_name]) => ({ id, name: gift_name, score: scores[id] || 0 })).sort((a,b)=>b.score-a.score);
  document.getElementById('quiz-form').classList.add('hidden');
  document.getElementById('progress-container').classList.add('hidden');
  document.getElementById('intro-card').classList.add('hidden');
  document.getElementById('res-name').textContent=name;
  document.getElementById('res-church').textContent=churchName;
  const top=document.getElementById('top-gifts-container'); top.innerHTML='';
  ['1º Dom Principal','2º Dom Secundário','3º Dom Terciário'].forEach((label,i)=>{
    const item=gifts[i]; if(!item)return;
    const card=document.createElement('div'); card.className='p-4 rounded-xl border bg-brand-50 border-brand-100 flex flex-col justify-between';
    card.innerHTML=`<div class="flex items-center justify-between mb-2"><span class="text-xs font-bold uppercase text-brand-700">${label}</span><span class="text-lg font-bold">${item.score} pts</span></div><h4 class="font-bold text-slate-900 text-sm">${escapeHtml(item.name)}</h4>`; top.appendChild(card);
  });
  const chart=document.getElementById('all-gifts-chart'); chart.innerHTML='';
  gifts.forEach(item=>{const pct=Math.min(Math.round((item.score/21)*100),100); const row=document.createElement('div');row.className='flex items-center justify-between gap-2 text-xs sm:text-sm';row.innerHTML=`<div class="w-1/3 truncate font-medium text-slate-700">${escapeHtml(item.name)}</div><div class="w-2/3 flex items-center space-x-2"><div class="w-full bg-slate-200 h-2 rounded-full overflow-hidden"><div class="bg-brand-600 h-full" style="width:${pct}%"></div></div><span class="font-bold w-8 text-right">${item.score}</span></div>`;chart.appendChild(row);});
  document.getElementById('results-card').classList.remove('hidden'); window.scrollTo({top:0,behavior:'smooth'});
}

window.restartQuiz = () => { if(confirm('Deseja refazer o teste? Suas respostas serão apagadas.')) { userAnswers={};currentPage=1;document.getElementById('quiz-form').classList.remove('hidden');document.getElementById('progress-container').classList.remove('hidden');document.getElementById('intro-card').classList.remove('hidden');document.getElementById('results-card').classList.add('hidden');renderPage(1); } };

function showValidationAlert(msg){document.getElementById('validation-message').textContent=msg;document.getElementById('validation-alert').classList.remove('hidden');}
function hideValidationAlert(){document.getElementById('validation-alert').classList.add('hidden');}
function escapeHtml(v){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));}

init();
