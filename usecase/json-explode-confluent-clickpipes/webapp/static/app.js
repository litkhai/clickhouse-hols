const $ = s => document.querySelector(s);
const api = (u, m, b) => fetch(u, {
  method: m || "GET",
  headers: {"Content-Type": "application/json"},
  body: b ? JSON.stringify(b) : undefined,
}).then(r => r.json());

// ---------------- i18n ----------------
const DB = document.body.dataset.db, TOPIC = document.body.dataset.topic;
const I18N = {
  ko: {
    title: "⚡ 실시간 JSON explode 데모",
    sub: `Confluent → ClickPipes → ClickHouse · <b>${DB}</b> / topic <b>${TOPIC}</b>`,
    interval: "interval", perMsg: "초/건",
    start: "▶ Start", stop: "⏸ Stop", cleanup: "🧹 Cleanup",
    stage_client: "Client — 메시지 생성", stage_kafka: "Kafka — 토픽 랜딩",
    stage_staging: "Staging — 변환 후", stage_fact: "Fact — 라인 단위 평탄화",
    arrow_produce: "▼ Kafka produce", arrow_ingest: "▼ ClickPipes 적재 + transform MV",
    arrow_explode: "▼ explode MV (ARRAY JOIN)",
    presets: "프리셋 쿼리", modal_title: "Kafka 메시지", copy: "복사", close: "✕ 닫기",
    result: "결과", result_hint: "버튼을 눌러보세요",
    producer: "Producer", running: "발행중", stopped: "정지", cumulative: "누적",
    recent: "최근", rows: "rows", lines: "lines",
    no_data: "— 데이터 없음 —", none_yet: "— 아직 없음 —", loading: "실행 중…",
    kafka_raw_col: "raw (클릭=전체)", kafka_tail: "Kafka tail",
    t_start: iv => `▶ 발행 시작 (${iv}s/건)`, t_running: "이미 발행 중",
    t_stop: "⏸ 정지 (Start로 재개)", t_interval: iv => `interval ${iv}s/건`,
    t_clean_ok: "🧹 초기화 완료 (0부터 다시)", t_clean_fail: e => "초기화 실패: " + e,
    t_copied: "복사됨", confirm_clean: "raw/staging/fact 테이블을 모두 비웁니다. 진행할까요?",
  },
  en: {
    title: "⚡ Real-time JSON explode demo",
    sub: `Confluent → ClickPipes → ClickHouse · <b>${DB}</b> / topic <b>${TOPIC}</b>`,
    interval: "interval", perMsg: "s/msg",
    start: "▶ Start", stop: "⏸ Stop", cleanup: "🧹 Cleanup",
    stage_client: "Client — message generation", stage_kafka: "Kafka — topic landing",
    stage_staging: "Staging — after transform", stage_fact: "Fact — flattened lines",
    arrow_produce: "▼ Kafka produce", arrow_ingest: "▼ ClickPipes ingest + transform MV",
    arrow_explode: "▼ explode MV (ARRAY JOIN)",
    presets: "Preset queries", modal_title: "Kafka message", copy: "Copy", close: "✕ Close",
    result: "Result", result_hint: "click a button",
    producer: "Producer", running: "producing", stopped: "stopped", cumulative: "sent",
    recent: "recent", rows: "rows", lines: "lines",
    no_data: "— no data —", none_yet: "— none yet —", loading: "running…",
    kafka_raw_col: "raw (click=full)", kafka_tail: "Kafka tail",
    t_start: iv => `▶ producing (${iv}s/msg)`, t_running: "already producing",
    t_stop: "⏸ stopped (Start to resume)", t_interval: iv => `interval ${iv}s/msg`,
    t_clean_ok: "🧹 cleaned (restart from 0)", t_clean_fail: e => "cleanup failed: " + e,
    t_copied: "copied", confirm_clean: "This truncates raw/staging/fact tables. Proceed?",
  },
};
let lang = localStorage.getItem("demoLang") || "ko";
const t = k => I18N[lang][k];

function applyLang(l){
  lang = l; localStorage.setItem("demoLang", l);
  document.documentElement.lang = l;
  document.querySelectorAll("[data-i18n]").forEach(el => {
    const v = I18N[l][el.dataset.i18n]; if (v !== undefined) el.textContent = v;
  });
  $("#sub").innerHTML = t("sub");
  $("#result-title").innerHTML = `${t("result")} <span class="hint">${t("result_hint")}</span>`;
  if (currentGroups) renderPresets(currentGroups);
  pollStatus(); pollStages();
}

// ---------------- helpers ----------------
function toast(msg){
  const el = $("#toast"); el.textContent = msg; el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 2200);
}
function esc(v){
  if (v === null || v === undefined || v === "None")
    return '<span class="null">NULL</span>';
  return String(v).replace(/[&<>]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
}
function renderTable(wrap, data){
  if (data.error){ wrap.innerHTML = `<div class="err">✗ ${esc(data.error)}</div>`; return; }
  const {columns, rows} = data;
  if (!rows || !rows.length){ wrap.innerHTML = `<div class="empty">${t("no_data")}</div>`; return; }
  let h = "<table><thead><tr>" + columns.map(c => `<th>${esc(c)}</th>`).join("") + "</tr></thead><tbody>";
  h += rows.map(r => "<tr>" + r.map(v => `<td>${esc(v)}</td>`).join("") + "</tr>").join("");
  wrap.innerHTML = h + "</tbody></table>";
}
function renderDicts(wrap, list, cols){
  if (!list || !list.length){ wrap.innerHTML = `<div class="empty">${t("none_yet")}</div>`; return; }
  let h = "<table><thead><tr>" + cols.map(c => `<th>${c.label}</th>`).join("") + "</tr></thead><tbody>";
  h += list.map(o => "<tr>" + cols.map(c =>
        `<td class="${c.mono?'mono':''}">${esc(o[c.key])}</td>`).join("") + "</tr>").join("");
  wrap.innerHTML = h + "</tbody></table>";
}

// ---------------- Kafka stage: raw JSON 모달 ----------------
let lastKafka = [];
function renderKafka(list){
  const wrap = $("#stage-kafka .tablewrap");
  lastKafka = list || [];
  if (!lastKafka.length){ wrap.innerHTML = `<div class="empty">${t("none_yet")}</div>`; return; }
  let h = `<table><thead><tr><th>P</th><th>offset</th><th>order</th><th>status</th><th>${t("kafka_raw_col")}</th></tr></thead><tbody>`;
  h += lastKafka.map((o,i) =>
      `<tr><td>${esc(o.partition)}</td><td>${esc(o.offset)}</td>`+
      `<td class="mono">${esc(o.order_id)}</td><td>${esc(o.order_status)}</td>`+
      `<td class="mono raw-cell" data-idx="${i}">${esc(o.raw)}</td></tr>`
    ).join("");
  wrap.innerHTML = h + "</tbody></table>";
}
function showJson(raw){
  let pretty = raw;
  try { pretty = JSON.stringify(JSON.parse(raw), null, 2); } catch(e){}
  $("#modal-body").textContent = pretty;
  $("#modal").classList.add("show");
}
function hideModal(){ $("#modal").classList.remove("show"); }
document.addEventListener("click", e => {
  const cell = e.target.closest(".raw-cell");
  if (cell){ const o = lastKafka[+cell.dataset.idx]; if (o) showJson(o.raw); }
});
$("#modal-close").onclick = hideModal;
$("#modal").onclick = e => { if (e.target.id === "modal") hideModal(); };
$("#modal-copy").onclick = () => navigator.clipboard.writeText($("#modal-body").textContent).then(() => toast(t("t_copied")));
document.addEventListener("keydown", e => { if (e.key === "Escape") hideModal(); });

// ---------------- 폴링 ----------------
async function pollStatus(){
  try{
    const s = await api("/api/status");
    const pipe = s.pipe || {};
    const pchip = $("#chip-pipe");
    pchip.innerHTML = `ClickPipe: <b>${esc(pipe.state)}</b>`;
    pchip.className = "chip " + (pipe.state === "Running" ? "on" : "warn");

    const prod = s.producer || {};
    const dchip = $("#chip-prod");
    dchip.innerHTML = `${t("producer")}: <b>${prod.running ? t("running") : t("stopped")}</b> · ${prod.interval}s · ${t("cumulative")} ${prod.sent}`;
    dchip.className = "chip " + (prod.running ? "on" : "off");
    $("#btn-start").disabled = prod.running;
    $("#btn-stop").disabled  = !prod.running;

    const c = s.counts || {};
    $("#chip-counts").innerHTML = c.error
      ? `<span style="color:var(--red)">${esc(c.error)}</span>`
      : `raw <b>${c.raw}</b> · staging <b>${c.staging}</b> · fact <b>${c.fact}</b>`;
    if (!c.error){
      $("#cnt-staging").textContent = c.staging + " " + t("rows");
      $("#cnt-fact").textContent    = c.fact + " " + t("lines");
    }
  }catch(e){}
}
async function pollStages(){
  try{
    const d = await api("/api/stages");
    if (d.error) return;
    renderDicts($("#stage-client .tablewrap"), d.client, [
      {key:"order_id",label:"order",mono:true},{key:"order_status",label:"status"},
      {key:"customer_id",label:"customer_id"},{key:"n_lines",label:"#lines"}]);
    $("#cnt-client").textContent = d.client.length ? `${d.client.length} (${t("recent")})` : "";

    if (d.kafka_error)
      $("#stage-kafka .tablewrap").innerHTML = `<div class="err">${t("kafka_tail")}: ${esc(d.kafka_error)}</div>`;
    else
      renderKafka(d.kafka);
    $("#cnt-kafka").textContent = d.kafka.length ? `${d.kafka.length} (${t("recent")})` : "";

    renderTable($("#stage-staging .tablewrap"), d.staging);
    renderTable($("#stage-fact .tablewrap"), d.fact);
  }catch(e){}
}

// ---------------- 컨트롤 ----------------
$("#lang").onchange = e => applyLang(e.target.value);
$("#btn-start").onclick = async () => {
  const interval = parseFloat($("#interval").value) || 3;
  const r = await api("/api/start", "POST", {interval});
  toast(r.resumed ? t("t_start")(interval) : t("t_running"));
  pollStatus();
};
$("#btn-stop").onclick = async () => { await api("/api/stop","POST"); toast(t("t_stop")); pollStatus(); };
$("#btn-clean").onclick = async () => {
  if (!confirm(t("confirm_clean"))) return;
  const r = await api("/api/cleanup","POST");
  toast(r.ok ? t("t_clean_ok") : t("t_clean_fail")(r.error));
  pollStatus(); pollStages();
};
$("#interval").onchange = async () => {
  const interval = parseFloat($("#interval").value) || 3;
  await api("/api/interval","POST",{interval}); toast(t("t_interval")(interval)); pollStatus();
};

// ---------------- 프리셋 ----------------
let currentGroups = null;
function renderPresets(groups){
  const root = $("#preset-grid");
  root.innerHTML = "";
  groups.forEach(g => {
    const cat = document.createElement("div");
    cat.className = "preset-cat";
    cat.innerHTML = `<h3>${esc(lang === "en" ? g.category_en : g.category)}</h3>`;
    const grid = document.createElement("div");
    grid.className = "preset-grid";
    g.items.forEach(p => {
      const label = lang === "en" ? p.label_en : p.label;
      const desc  = lang === "en" ? p.desc_en  : p.desc;
      const b = document.createElement("button");
      b.title = desc + "\n\n" + p.sql;
      b.innerHTML = `<span class="plabel">${esc(label)}</span><span class="pdesc">${esc(desc)}</span>`;
      b.onclick = async () => {
        document.querySelectorAll(".preset-grid button").forEach(x => x.classList.remove("active"));
        b.classList.add("active");
        $("#result-title").innerHTML = `${t("result")} <span class="hint">${esc(label)}</span>`;
        $("#result-desc").textContent = desc;
        $("#result-wrap").innerHTML = `<div class="empty">${t("loading")}</div>`;
        renderTable($("#result-wrap"), await api("/api/query","POST",{id:p.id}));
      };
      grid.appendChild(b);
    });
    cat.appendChild(grid);
    root.appendChild(cat);
  });
}
async function loadPresets(){
  currentGroups = await api("/api/presets");
  renderPresets(currentGroups);
}

// ---------------- init ----------------
$("#lang").value = lang;
applyLang(lang);
loadPresets();
setInterval(pollStatus, 2000);
setInterval(pollStages, 2500);
