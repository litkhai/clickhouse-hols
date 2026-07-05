const $ = s => document.querySelector(s);
const api = (u, m, b) => fetch(u, {
  method: m || "GET",
  headers: {"Content-Type": "application/json"},
  body: b ? JSON.stringify(b) : undefined,
}).then(r => r.json());

function toast(msg){
  const t = $("#toast"); t.textContent = msg; t.classList.add("show");
  setTimeout(() => t.classList.remove("show"), 2200);
}

function esc(v){
  if (v === null || v === undefined || v === "None")
    return '<span class="null">NULL</span>';
  return String(v).replace(/[&<>]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
}

// columns+rows 형태 렌더
function renderTable(wrap, data){
  if (data.error){ wrap.innerHTML = `<div class="err">✗ ${esc(data.error)}</div>`; return; }
  const {columns, rows} = data;
  if (!rows || !rows.length){ wrap.innerHTML = `<div class="empty">— 데이터 없음 —</div>`; return; }
  let h = "<table><thead><tr>" + columns.map(c => `<th>${esc(c)}</th>`).join("") + "</tr></thead><tbody>";
  h += rows.map(r => "<tr>" + r.map(v => `<td>${esc(v)}</td>`).join("") + "</tr>").join("");
  wrap.innerHTML = h + "</tbody></table>";
}

// list-of-dicts 형태 렌더 (지정 컬럼)
function renderDicts(wrap, list, cols){
  if (!list || !list.length){ wrap.innerHTML = `<div class="empty">— 아직 없음 —</div>`; return; }
  let h = "<table><thead><tr>" + cols.map(c => `<th>${c.label}</th>`).join("") + "</tr></thead><tbody>";
  h += list.map(o => "<tr>" + cols.map(c =>
        `<td class="${c.mono?'mono':''}">${esc(o[c.key])}</td>`).join("") + "</tr>").join("");
  wrap.innerHTML = h + "</tbody></table>";
}

// ---------- Kafka 단계: raw JSON 클릭 → 전체 보기 모달 ----------
let lastKafka = [];
function renderKafka(list){
  const wrap = $("#stage-kafka .tablewrap");
  lastKafka = list || [];
  if (!lastKafka.length){ wrap.innerHTML = `<div class="empty">— 아직 없음 —</div>`; return; }
  let h = "<table><thead><tr><th>P</th><th>offset</th><th>order</th><th>status</th><th>raw (클릭=전체)</th></tr></thead><tbody>";
  h += lastKafka.map((o,i) =>
      `<tr><td>${esc(o.partition)}</td><td>${esc(o.offset)}</td>`+
      `<td class="mono">${esc(o.order_id)}</td><td>${esc(o.order_status)}</td>`+
      `<td class="mono raw-cell" data-idx="${i}" title="클릭하여 전체 JSON 보기">${esc(o.raw)}</td></tr>`
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

document.addEventListener("click", (e) => {
  const cell = e.target.closest(".raw-cell");
  if (cell){ const o = lastKafka[+cell.dataset.idx]; if (o) showJson(o.raw); }
});
$("#modal-close").onclick = hideModal;
$("#modal").onclick = (e) => { if (e.target.id === "modal") hideModal(); };
$("#modal-copy").onclick = () => {
  navigator.clipboard.writeText($("#modal-body").textContent).then(() => toast("복사됨"));
};
document.addEventListener("keydown", (e) => { if (e.key === "Escape") hideModal(); });

// ---------- 상태 폴링 ----------
async function pollStatus(){
  try{
    const s = await api("/api/status");
    const pipe = s.pipe || {};
    const pchip = $("#chip-pipe");
    pchip.innerHTML = `ClickPipe: <b>${esc(pipe.state)}</b>`;
    pchip.className = "chip " + (pipe.state === "Running" ? "on" : "warn");

    const prod = s.producer || {};
    const dchip = $("#chip-prod");
    dchip.innerHTML = `Producer: <b>${prod.running ? "발행중" : "정지"}</b> · ${prod.interval}s/건 · 누적 ${prod.sent}`;
    dchip.className = "chip " + (prod.running ? "on" : "off");
    $("#btn-start").disabled = prod.running;
    $("#btn-stop").disabled  = !prod.running;

    const c = s.counts || {};
    $("#chip-counts").innerHTML = c.error
      ? `<span style="color:var(--red)">${esc(c.error)}</span>`
      : `raw <b>${c.raw}</b> · staging <b>${c.staging}</b> · fact <b>${c.fact}</b>`;
    if(!c.error){
      $("#cnt-staging").textContent = c.staging + " rows";
      $("#cnt-fact").textContent    = c.fact + " lines";
    }
  }catch(e){ /* 무시 */ }
}

async function pollStages(){
  try{
    const d = await api("/api/stages");
    if (d.error) return;
    renderDicts($("#stage-client .tablewrap"), d.client, [
      {key:"order_id",label:"order",mono:true},{key:"order_status",label:"status"},
      {key:"customer_id",label:"customer_id"},{key:"n_lines",label:"#lines"}]);
    $("#cnt-client").textContent = d.client.length ? d.client.length + " (최근)" : "";

    if (d.kafka_error)
      $("#stage-kafka .tablewrap").innerHTML = `<div class="err">Kafka tail: ${esc(d.kafka_error)}</div>`;
    else
      renderKafka(d.kafka);
    $("#cnt-kafka").textContent = d.kafka.length ? d.kafka.length + " (최근)" : "";

    renderTable($("#stage-staging .tablewrap"), d.staging);
    renderTable($("#stage-fact .tablewrap"), d.fact);
  }catch(e){ /* 무시 */ }
}

// ---------- 컨트롤 ----------
$("#btn-start").onclick = async () => {
  const interval = parseFloat($("#interval").value) || 3;
  const r = await api("/api/start", "POST", {interval});
  toast(r.resumed ? `▶ 발행 시작 (${interval}s/건)` : "이미 발행 중");
  pollStatus();
};
$("#btn-stop").onclick = async () => { await api("/api/stop","POST"); toast("⏸ 정지 (Start로 재개)"); pollStatus(); };
$("#btn-clean").onclick = async () => {
  if(!confirm("raw/staging/fact 테이블을 모두 비웁니다. 진행할까요?")) return;
  const r = await api("/api/cleanup","POST");
  toast(r.ok ? "🧹 초기화 완료 (0부터 다시)" : "초기화 실패: " + r.error);
  pollStatus(); pollStages();
};
$("#interval").onchange = async () => {
  const interval = parseFloat($("#interval").value) || 3;
  await api("/api/interval","POST",{interval}); toast(`interval ${interval}s/건`); pollStatus();
};

// ---------- 프리셋 (카테고리별) ----------
async function loadPresets(){
  const groups = await api("/api/presets");
  const root = $("#preset-grid");
  root.innerHTML = "";
  groups.forEach(g => {
    const cat = document.createElement("div");
    cat.className = "preset-cat";
    cat.innerHTML = `<h3>${esc(g.category)}</h3>`;
    const grid = document.createElement("div");
    grid.className = "preset-grid";
    g.items.forEach(p => {
      const b = document.createElement("button");
      b.title = p.desc + "\n\n" + p.sql;
      b.innerHTML = `<span class="plabel">${esc(p.label)}</span><span class="pdesc">${esc(p.desc)}</span>`;
      b.onclick = async () => {
        document.querySelectorAll(".preset-grid button").forEach(x => x.classList.remove("active"));
        b.classList.add("active");
        $("#result-title").innerHTML = `결과 <span class="hint">${esc(p.label)}</span>`;
        $("#result-desc").textContent = p.desc;
        $("#result-wrap").innerHTML = `<div class="empty">실행 중…</div>`;
        renderTable($("#result-wrap"), await api("/api/query","POST",{id:p.id}));
      };
      grid.appendChild(b);
    });
    cat.appendChild(grid);
    root.appendChild(cat);
  });
}

loadPresets();
pollStatus(); pollStages();
setInterval(pollStatus, 2000);
setInterval(pollStages, 2500);
