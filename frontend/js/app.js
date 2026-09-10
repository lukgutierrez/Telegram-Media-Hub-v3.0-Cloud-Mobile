// Telegram Media Hub v3.0 - Frontend Controller
const API_BASE = window.location.origin + "/api/v1";
let token = localStorage.getItem("tmh_token");
let currentUser = null;
let ws = null;
let currentAuthMode = "login";
let activeJobId = null;
let currentTopicsList = [];

document.addEventListener("DOMContentLoaded", () => {
    if (token) {
        initApp();
    } else {
        showAuthView();
    }
});

function showAuthView() {
    document.getElementById("view-auth").classList.remove("hidden");
    document.getElementById("view-dashboard").classList.add("hidden");
    document.getElementById("nav-user-section").classList.add("hidden");
}

function showDashboardView() {
    document.getElementById("view-auth").classList.add("hidden");
    document.getElementById("view-dashboard").classList.remove("hidden");
    document.getElementById("nav-user-section").classList.remove("hidden");
}

function switchAuthTab(mode) {
    currentAuthMode = mode;
    const btnLogin = document.getElementById("tab-btn-login");
    const btnRegister = document.getElementById("tab-btn-register");
    const submitBtn = document.getElementById("auth-submit-btn");

    if (mode === "login") {
        btnLogin.className = "flex-1 py-2 text-sm font-semibold rounded-md bg-cyan-500 text-slate-950 transition";
        btnRegister.className = "flex-1 py-2 text-sm font-semibold rounded-md text-slate-400 hover:text-white transition";
        submitBtn.innerHTML = '<i class="fa-solid fa-arrow-right-to-bracket"></i> Iniciar Sesión';
    } else {
        btnRegister.className = "flex-1 py-2 text-sm font-semibold rounded-md bg-cyan-500 text-slate-950 transition";
        btnLogin.className = "flex-1 py-2 text-sm font-semibold rounded-md text-slate-400 hover:text-white transition";
        submitBtn.innerHTML = '<i class="fa-solid fa-user-plus"></i> Crear Cuenta';
    }
}

async function handleAuthSubmit(e) {
    e.preventDefault();
    const email = document.getElementById("auth-email").value.trim();
    const password = document.getElementById("auth-password").value;
    const errBox = document.getElementById("auth-error");
    errBox.classList.add("hidden");

    try {
        let endpoint = currentAuthMode === "login" ? `${API_BASE}/auth/login` : `${API_BASE}/auth/register`;
        let body;
        let headers = {};

        if (currentAuthMode === "login") {
            const formData = new URLSearchParams();
            formData.append("username", email);
            formData.append("password", password);
            body = formData;
            headers["Content-Type"] = "application/x-www-form-urlencoded";
        } else {
            body = JSON.stringify({ email, password });
            headers["Content-Type"] = "application/json";
        }

        const res = await fetch(endpoint, { method: "POST", headers, body });
        const data = await res.json();

        if (!res.ok) {
            throw new Error(data.detail || "Error en autenticación");
        }

        token = data.access_token;
        localStorage.setItem("tmh_token", token);
        initApp();

    } catch (err) {
        errBox.innerText = err.message;
        errBox.classList.remove("hidden");
    }
}

function openForgotModal() {
    const loginEmail = document.getElementById("auth-email").value.trim();
    if (loginEmail) {
        document.getElementById("forgot-email").value = loginEmail;
    }
    const statusBox = document.getElementById("forgot-status");
    statusBox.className = "text-xs p-2.5 rounded hidden";
    document.getElementById("modal-forgot").classList.remove("hidden");
}

function closeForgotModal() {
    document.getElementById("modal-forgot").classList.add("hidden");
}

async function handleForgotSubmit(e) {
    e.preventDefault();
    const email = document.getElementById("forgot-email").value.trim();
    const new_password = document.getElementById("forgot-new-password").value;
    const statusBox = document.getElementById("forgot-status");
    const btnSave = document.getElementById("btn-save-new-pass");

    statusBox.className = "text-xs p-2.5 rounded hidden";
    btnSave.disabled = true;
    btnSave.innerText = "Guardando...";

    try {
        const res = await fetch(`${API_BASE}/auth/reset-password`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email, new_password })
        });
        const data = await res.json();
        if (!res.ok) {
            throw new Error(data.detail || "Error al restablecer la contraseña.");
        }

        statusBox.className = "text-xs text-emerald-300 bg-emerald-500/10 p-2.5 rounded border border-emerald-500/30";
        statusBox.innerText = "¡Contraseña actualizada con éxito! Ya puedes iniciar sesión.";
        statusBox.classList.remove("hidden");

        setTimeout(() => {
            closeForgotModal();
            document.getElementById("auth-email").value = email;
            document.getElementById("auth-password").value = new_password;
            const successBox = document.getElementById("auth-success");
            successBox.innerText = "Contraseña restablecida. Puedes iniciar sesión ahora.";
            successBox.classList.remove("hidden");
        }, 1200);

    } catch (err) {
        statusBox.className = "text-xs text-red-400 bg-red-500/10 p-2.5 rounded border border-red-500/20";
        statusBox.innerText = err.message;
        statusBox.classList.remove("hidden");
    } finally {
        btnSave.disabled = false;
        btnSave.innerText = "Guardar Nueva Clave";
    }
}

// --- VINCULACIÓN DE APP MÓVIL POR QR / PIN ---
let qrSyncTimerInterval = null;

async function openQrSyncModal() {
    document.getElementById("modal-qr-sync").classList.remove("hidden");
    await generateNewQuickCode();
}

function closeQrSyncModal() {
    document.getElementById("modal-qr-sync").classList.add("hidden");
    if (qrSyncTimerInterval) {
        clearInterval(qrSyncTimerInterval);
        qrSyncTimerInterval = null;
    }
}

async function generateNewQuickCode() {
    if (qrSyncTimerInterval) {
        clearInterval(qrSyncTimerInterval);
        qrSyncTimerInterval = null;
    }
    const pinEl = document.getElementById("qr-sync-pin");
    const timerEl = document.getElementById("qr-sync-timer");
    const qrContainer = document.getElementById("qr-code-canvas");
    
    pinEl.innerText = "GENERANDO...";
    qrContainer.innerHTML = '<div class="text-xs text-slate-500 py-16"><i class="fa-solid fa-spinner fa-spin text-2xl text-cyan-500"></i></div>';
    
    try {
        const res = await fetch(`${API_BASE}/auth/quick-code/generate`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`
            }
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error al generar código");
        
        pinEl.innerText = data.code;
        
        // Render QR Code
        qrContainer.innerHTML = "";
        if (typeof QRCode !== "undefined") {
            new QRCode(qrContainer, {
                text: data.qr_payload || data.code,
                width: 170,
                height: 170,
                colorDark: "#000000",
                colorLight: "#ffffff",
                correctLevel: QRCode.CorrectLevel.M
            });
        }
        
        // Iniciar cuenta regresiva
        let remaining = data.expires_in_seconds || 300;
        function updateTimer() {
            const m = Math.floor(remaining / 60).toString().padStart(2, '0');
            const s = (remaining % 60).toString().padStart(2, '0');
            timerEl.innerHTML = `<i class="fa-solid fa-clock"></i> Expira en: ${m}:${s}`;
            if (remaining <= 0) {
                clearInterval(qrSyncTimerInterval);
                timerEl.innerHTML = `<i class="fa-solid fa-triangle-exclamation text-red-400"></i> Código expirado`;
                pinEl.innerText = "EXPIRADO";
            }
            remaining--;
        }
        updateTimer();
        qrSyncTimerInterval = setInterval(updateTimer, 1000);
        
    } catch (e) {
        pinEl.innerText = "ERROR";
        timerEl.innerText = e.message;
    }
}

function copyPinCode() {
    const pin = document.getElementById("qr-sync-pin").innerText;
    if (pin && pin !== "EXPIRADO" && pin !== "GENERANDO...") {
        navigator.clipboard.writeText(pin);
        alert(`Código PIN ${pin} copiado.`);
    }
}

function logout() {
    localStorage.removeItem("tmh_token");
    token = null;
    currentUser = null;
    if (ws) ws.close();
    showAuthView();
}

async function initApp() {
    try {
        const res = await fetch(`${API_BASE}/auth/me`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        if (!res.ok) {
            logout();
            return;
        }
        currentUser = await res.json();
        document.getElementById("nav-user-email").innerText = currentUser.email;
        showDashboardView();
        updateConnectionCards();
        initWebSocket();
        loadJobsHistory();
        loadDedupStats();
    } catch (err) {
        logout();
    }
}

function updateConnectionCards() {
    // Telegram Status
    const tgBadge = document.getElementById("status-badge-telegram");
    const btnTg = document.getElementById("btn-tg-action");
    if (currentUser.telegram_connected) {
        tgBadge.className = "mt-0.5 inline-block status-badge status-connected";
        tgBadge.innerText = "Conectado ✅";
        btnTg.innerText = "Desconectar";
        btnTg.onclick = disconnectTelegram;
    } else {
        tgBadge.className = "mt-0.5 inline-block status-badge status-disconnected";
        tgBadge.innerText = "Desconectado ❌";
        btnTg.innerText = "Conectar";
        btnTg.onclick = openTelegramModal;
    }

    // Drive Status
    const drBadge = document.getElementById("status-badge-drive");
    const btnDr = document.getElementById("btn-drive-action");
    if (currentUser.drive_connected) {
        drBadge.className = "mt-0.5 inline-block status-badge status-connected";
        drBadge.innerText = "Conectado ✅";
        btnDr.innerText = "Desconectar";
        btnDr.onclick = disconnectDrive;
    } else {
        drBadge.className = "mt-0.5 inline-block status-badge status-disconnected";
        drBadge.innerText = "Desconectado ❌";
        btnDr.innerText = "Conectar (Opcional)";
        btnDr.onclick = connectGoogleDrive;
    }
}

function initWebSocket() {
    if (!currentUser) return;
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.host}/ws/progress/${currentUser.id}`;
    ws = new WebSocket(wsUrl);

    ws.onmessage = (event) => {
        try {
            const data = JSON.parse(event.data);
            handleLiveProgress(data);
        } catch (e) {}
    };

    ws.onclose = () => {
        setTimeout(initWebSocket, 3000);
    };
}

function handleLiveProgress(data) {
    if (data.job_id) {
        activeJobId = data.job_id;
    }
    const box = document.getElementById("active-job-box");
    box.classList.remove("hidden");

    document.getElementById("active-job-pct").innerText = `${data.progress || 0}%`;
    document.getElementById("active-job-bar").style.width = `${data.progress || 0}%`;
    
    const statusEl = document.getElementById("active-job-status");
    const st = data.status || "PROCESANDO";
    statusEl.innerText = st;

    const btnPause = document.getElementById("btn-job-pause");
    const btnResume = document.getElementById("btn-job-resume");

    if (st === "PAUSED") {
        statusEl.className = "status-badge status-paused";
        btnPause.classList.add("hidden");
        btnResume.classList.remove("hidden");
    } else {
        statusEl.className = st === "COMPLETED" ? "status-badge status-connected" : (st === "FAILED" || st === "CANCELLED" ? "status-badge status-disconnected" : "status-badge status-running");
        btnPause.classList.remove("hidden");
        btnResume.classList.add("hidden");
    }

    document.getElementById("active-job-speed").innerText = `${data.speed_mbs || 0} MB/s`;
    
    let eta = data.eta_seconds || 0;
    let etaStr = eta > 60 ? `${Math.floor(eta / 60)}m ${eta % 60}s` : `${eta}s`;
    document.getElementById("active-job-eta").innerText = eta > 0 ? etaStr : "--:--";
    document.getElementById("active-job-files-count").innerText = `${data.processed_files || 0} / ${data.total_files || 0}`;

    if (data.current_file) {
        document.getElementById("active-job-current-file").innerText = `📄 ${data.current_file}`;
    }

    if (data.status === "COMPLETED") {
        document.getElementById("active-job-current-file").innerText = `🎉 ¡Descarga completada con éxito! Revisa los archivos abajo.`;
        loadJobsHistory();
        refreshCurrentJobFiles();
        loadDedupStats();
    } else if (data.status === "FAILED") {
        document.getElementById("active-job-current-file").innerText = `❌ Error: ${data.error || 'Fallo en la tarea'}`;
        loadJobsHistory();
    }
}

function switchTab(tabId) {
    const tabs = ["downloader", "forum", "jobs", "osint", "dedup", "search"];
    tabs.forEach(t => {
        const content = document.getElementById(`tab-content-${t}`);
        const nav = document.getElementById(`tab-nav-${t}`);
        if (content) content.classList.add("hidden");
        if (nav) nav.className = "px-4 py-2 rounded-lg text-slate-400 hover:text-white font-bold text-xs sm:text-sm flex items-center gap-2 whitespace-nowrap";
    });

    const activeContent = document.getElementById(`tab-content-${tabId}`);
    const activeNav = document.getElementById(`tab-nav-${tabId}`);
    if (activeContent) activeContent.classList.remove("hidden");
    if (activeNav) activeNav.className = "px-4 py-2 rounded-lg bg-cyan-500/10 text-cyan-400 border border-cyan-500/30 font-bold text-xs sm:text-sm flex items-center gap-2 whitespace-nowrap";

    if (tabId === "jobs") {
        loadJobsHistory();
        if (activeJobId) refreshCurrentJobFiles();
    } else if (tabId === "dedup") {
        loadDedupStats();
    } else if (tabId === "search") {
        const inp = document.getElementById("input-tg-global-search");
        if (inp) inp.focus();
    }
}

function handleJobTypeChange() {
    const val = document.getElementById("select-job-type").value;
    const batchBox = document.getElementById("batch-options-box");
    if (val === "BATCH_CHANNEL") {
        batchBox.classList.remove("hidden");
    } else {
        batchBox.classList.add("hidden");
    }
}

// -------------------------------------------------------------
// PESTAÑA 1: DESCARGADOR RÁPIDO
// -------------------------------------------------------------
async function startDownloadJob() {
    const targetUrl = document.getElementById("input-target-url").value.trim();
    const destination = document.getElementById("select-destination").value;
    const jobType = document.getElementById("select-job-type").value;
    const mediaFilter = document.getElementById("select-media-filter").value;
    const concurrency = parseInt(document.getElementById("slider-concurrency").value) || 10;
    const invertOrder = document.getElementById("check-invert-order").checked;
    const batchLimit = parseInt(document.getElementById("input-batch-limit").value) || 100;

    if (!targetUrl) {
        alert("Por favor ingresa un enlace o ID de Telegram válido.");
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/jobs/`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                target_url: targetUrl,
                destination: destination,
                job_type: jobType,
                concurrency: concurrency,
                invert_order: invertOrder,
                limit_messages: jobType === "BATCH_CHANNEL" ? batchLimit : null,
                media_filter: mediaFilter
            })
        });

        const data = await res.json();
        if (!res.ok) {
            alert(data.detail || "Error al iniciar la tarea.");
            return;
        }

        activeJobId = data.id;
        switchTab("jobs");
        handleLiveProgress({
            job_id: data.id,
            status: "INICIANDO",
            progress: 0,
            speed_mbs: 0,
            eta_seconds: 0
        });

    } catch (err) {
        alert("Error de conexión con el servidor.");
    }
}

// -------------------------------------------------------------
// PESTAÑA 2: DESCARGADOR DE FOROS (TOPICS)
// -------------------------------------------------------------
async function loadAndPreAnalyzeTopics() {
    const target = document.getElementById("input-forum-target").value.trim();
    if (!target) return alert("Por favor ingresa el ID o enlace del grupo Foro.");

    const loadingBox = document.getElementById("forum-loading-box");
    const container = document.getElementById("forum-preanalysis-container");
    loadingBox.classList.remove("hidden");
    container.classList.add("hidden");

    try {
        const res = await fetch(`${API_BASE}/osint/pre-analyze-topics`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                target: target,
                concurrency: 10
            })
        });

        const data = await res.json();
        loadingBox.classList.add("hidden");

        if (!res.ok) {
            alert(data.detail || "Error pre-analizando topics.");
            return;
        }

        currentTopicsList = data.topics || [];
        const summary = data.summary || {};

        document.getElementById("pre-tot-topics").innerText = summary.total_topics || 0;
        document.getElementById("pre-tot-photos").innerText = summary.total_photos || 0;
        document.getElementById("pre-tot-videos").innerText = summary.total_videos || 0;
        document.getElementById("pre-tot-mb").innerText = `${summary.total_mb || 0} MB`;
        document.getElementById("pre-tot-eta").innerText = summary.eta_formatted || "--:--";

        const tbody = document.getElementById("tbody-topics-list");
        tbody.innerHTML = currentTopicsList.map(t => `
            <tr>
                <td class="text-center">
                    <input type="checkbox" value="${t.id}" class="topic-checkbox w-4 h-4 rounded border-slate-700 bg-slate-900 text-cyan-500" onchange="updateSelectedTopicsCount()" checked>
                </td>
                <td class="font-mono text-cyan-400 text-xs">${t.id}</td>
                <td class="font-semibold text-white">${t.title}</td>
                <td class="text-center font-mono text-[#00F0FF]">${t.photos}</td>
                <td class="text-center font-mono text-[#00FF41]">${t.videos}</td>
                <td class="text-center font-mono text-slate-400">${t.other}</td>
                <td class="text-center font-bold text-white">${t.total_files}</td>
                <td class="text-right font-mono font-bold text-[#FFE600]">${t.size_mb} MB</td>
            </tr>
        `).join("");

        updateSelectedTopicsCount();
        container.classList.remove("hidden");

    } catch (e) {
        loadingBox.classList.add("hidden");
        alert("Error de conexión al obtener topics.");
    }
}

function toggleSelectAllTopics(checked) {
    const checkboxes = document.querySelectorAll(".topic-checkbox");
    checkboxes.forEach(cb => cb.checked = checked);
    document.getElementById("check-all-topics").checked = checked;
    updateSelectedTopicsCount();
}

function updateSelectedTopicsCount() {
    const selected = document.querySelectorAll(".topic-checkbox:checked");
    document.getElementById("label-selected-topics-count").innerText = `${selected.length} seleccionados`;
}

async function startForumDownload(downloadAll) {
    const target = document.getElementById("input-forum-target").value.trim();
    if (!target) return alert("Ingresa el ID del grupo foro.");

    let topicIds = [];
    if (!downloadAll) {
        const checkboxes = document.querySelectorAll(".topic-checkbox:checked");
        topicIds = Array.from(checkboxes).map(cb => parseInt(cb.value));
        if (topicIds.length === 0) {
            alert("Selecciona al menos un topic para descargar.");
            return;
        }
    }

    const destination = document.getElementById("forum-select-destination").value;
    const mediaFilter = document.getElementById("forum-select-filter").value;
    const invertOrder = document.getElementById("forum-check-invert").checked;

    try {
        const res = await fetch(`${API_BASE}/jobs/`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                target_url: target,
                destination: destination,
                job_type: "FORUM_TOPICS",
                selected_topic_ids: downloadAll ? null : topicIds,
                concurrency: 10,
                invert_order: invertOrder,
                media_filter: mediaFilter
            })
        });

        const data = await res.json();
        if (!res.ok) {
            alert(data.detail || "Error al iniciar la descarga de foros.");
            return;
        }

        activeJobId = data.id;
        switchTab("jobs");
        handleLiveProgress({
            job_id: data.id,
            status: "INICIANDO",
            progress: 0,
            speed_mbs: 0,
            eta_seconds: 0
        });

    } catch (e) {
        alert("Error de conexión con el servidor.");
    }
}

// -------------------------------------------------------------
// PESTAÑA 3: MONITOR, CONTROLES & DESCARGAS DIRECTAS
// -------------------------------------------------------------
async function controlJobAction(action) {
    if (!activeJobId) return;
    try {
        const res = await fetch(`${API_BASE}/jobs/${activeJobId}/action`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ action })
        });
        const data = await res.json();
        if (!res.ok) alert(data.detail || "Error al enviar señal");
    } catch (e) {
        alert("Error de conexión con el servidor.");
    }
}

async function refreshCurrentJobFiles() {
    if (!activeJobId) return;
    loadJobFiles(activeJobId);
}

async function loadJobFiles(jobId) {
    activeJobId = jobId;
    try {
        const res = await fetch(`${API_BASE}/jobs/${jobId}/files`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        const files = await res.json();
        const tbody = document.getElementById("tbody-job-files");
        const zipBtn = document.getElementById("btn-download-all-zip");
        document.getElementById("job-files-count-label").innerText = files.length;

        const hasAnyLocal = files && files.some(f => f.has_local_download);
        if (zipBtn) {
            if (hasAnyLocal) {
                zipBtn.href = `${API_BASE}/jobs/${jobId}/download-zip?token=${token}`;
                zipBtn.classList.remove("hidden");
            } else {
                zipBtn.classList.add("hidden");
            }
        }

        if (!files || files.length === 0) {
            tbody.innerHTML = `<tr><td colspan="5" class="text-center text-slate-500 py-4">No hay archivos registrados aún para esta tarea.</td></tr>`;
            return;
        }

        tbody.innerHTML = files.map(f => {
            let actionBtn = "";
            if (f.has_local_download && f.download_url) {
                const dlUrl = `${f.download_url}?token=${token}`;
                actionBtn = `<a href="${dlUrl}" download="${f.filename}" class="px-2.5 py-1 rounded bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 border border-cyan-500/30 text-xs font-bold inline-flex items-center gap-1 transition"><i class="fa-solid fa-download"></i> Descargar</a>`;
            } else if (f.drive_link) {
                actionBtn = `<a href="${f.drive_link}" target="_blank" class="px-2.5 py-1 rounded bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/30 text-xs font-bold inline-flex items-center gap-1"><i class="fa-brands fa-google-drive"></i> Drive</a>`;
            } else {
                actionBtn = `<span class="text-slate-500 text-xs">Guardado</span>`;
            }

            let statusBadge = `<span class="status-badge status-connected">${f.status}</span>`;
            if (f.status === "DEDUP_SKIPPED") {
                statusBadge = `<span class="status-badge bg-purple-500/20 text-purple-300 border border-purple-500/30">DEDUP ⚡</span>`;
            }

            return `
                <tr>
                    <td class="font-semibold text-white max-w-xs truncate" title="${f.filename}">📄 ${f.filename}</td>
                    <td class="text-center font-mono font-bold text-[#FFE600]">${f.size_mb} MB</td>
                    <td class="font-mono text-xs text-slate-400 truncate max-w-[120px]" title="${f.sha256}">${f.sha256 ? f.sha256.substring(0, 10) + '...' : '-'}</td>
                    <td class="text-center">${statusBadge}</td>
                    <td class="text-right">${actionBtn}</td>
                </tr>
            `;
        }).join("");

    } catch (e) {}
}

async function loadJobsHistory() {
    try {
        const res = await fetch(`${API_BASE}/jobs/`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        const jobs = await res.json();
        const container = document.getElementById("jobs-history-list");
        
        if (!jobs || jobs.length === 0) {
            container.innerHTML = '<p class="text-xs text-slate-500">No hay tareas recientes.</p>';
            return;
        }

        container.innerHTML = jobs.map(j => {
            const hasZip = j.destination === "DIRECT_DOWNLOAD" && j.processed_files > 0;
            return `
            <div class="p-3 bg-slate-900/40 rounded-lg border border-slate-800 flex items-center justify-between text-xs cursor-pointer hover:border-cyan-500/30 transition" onclick="loadJobFiles(${j.id})">
                <div class="flex flex-col gap-0.5 truncate mr-2">
                    <span class="font-bold text-white truncate"><span class="text-cyan-400">#${j.id}</span> ${j.target_url}</span>
                    <span class="text-slate-400 font-mono">Modo: ${j.job_type} &bull; Destino: ${j.destination} &bull; Archivos: ${j.processed_files}/${j.total_files}</span>
                </div>
                <div class="flex items-center gap-2">
                    ${hasZip ? `<a href="${API_BASE}/jobs/${j.id}/download-zip?token=${token}" onclick="event.stopPropagation();" class="px-2.5 py-1 rounded bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/30 font-bold inline-flex items-center gap-1"><i class="fa-solid fa-file-zipper"></i> ZIP</a>` : ''}
                    <span class="status-badge ${j.status === 'COMPLETED' ? 'status-connected' : (j.status === 'FAILED' ? 'status-disconnected' : 'status-running')}">${j.status}</span>
                </div>
            </div>
            `;
        }).join("");

    } catch (e) {}
}

// -------------------------------------------------------------
// PESTAÑA 4: CENTRO OSINT COMPLETO
// -------------------------------------------------------------
function switchOsintSubTab(subtab) {
    const subtabs = ["chats", "info", "stats", "search", "recent"];
    subtabs.forEach(s => {
        const panel = document.getElementById(`osint-subpanel-${s}`);
        const btn = document.getElementById(`subtab-osint-${s}`);
        if (panel) panel.classList.add("hidden");
        if (btn) btn.className = "px-3 py-1.5 rounded-md text-slate-400 hover:text-white";
    });

    const activePanel = document.getElementById(`osint-subpanel-${subtab}`);
    const activeBtn = document.getElementById(`subtab-osint-${subtab}`);
    if (activePanel) activePanel.classList.remove("hidden");
    if (activeBtn) activeBtn.className = "px-3 py-1.5 rounded-md bg-cyan-500/20 text-cyan-400 border border-cyan-500/30";

    if (subtab === "chats") {
        loadMyChats();
    }
}

async function loadMyChats() {
    const tbody = document.getElementById("tbody-my-chats");
    tbody.innerHTML = `<tr><td colspan="6" class="text-center text-cyan-400 py-4"><i class="fa-solid fa-circle-notch fa-spin"></i> Cargando tus grupos y canales...</td></tr>`;

    try {
        const res = await fetch(`${API_BASE}/osint/my-chats`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        const chats = await res.json();

        if (!res.ok) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center text-red-400 py-4">${chats.detail || "Error obteniendo chats"}</td></tr>`;
            return;
        }

        if (!chats || chats.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center text-slate-500 py-4">No se encontraron chats o canales.</td></tr>`;
            return;
        }

        tbody.innerHTML = chats.map(c => `
            <tr>
                <td class="font-bold text-white">${c.title}</td>
                <td class="font-mono text-cyan-400 font-bold">${c.id}</td>
                <td><span class="px-2 py-0.5 rounded text-[11px] font-semibold ${c.is_forum ? 'bg-purple-500/20 text-purple-300 border border-purple-500/30' : 'bg-slate-800 text-slate-300'}">${c.type}</span></td>
                <td class="font-mono text-xs text-slate-400">${c.username}</td>
                <td class="font-mono text-xs text-slate-300">${c.members}</td>
                <td class="text-right">
                    <div class="flex items-center justify-end gap-1.5">
                        <button onclick="navigator.clipboard.writeText('${c.id}'); alert('ID ${c.id} copiado');" class="px-2 py-1 rounded bg-slate-800 hover:bg-slate-700 text-xs text-slate-300" title="Copiar ID"><i class="fa-solid fa-copy"></i></button>
                        <button onclick="useTargetInDownloader('${c.id}', ${c.is_forum})" class="px-2 py-1 rounded bg-cyan-500/20 hover:bg-cyan-500/30 text-xs text-cyan-300 font-bold">Usar</button>
                    </div>
                </td>
            </tr>
        `).join("");

    } catch (e) {
        tbody.innerHTML = `<tr><td colspan="6" class="text-center text-red-400 py-4">Error de conexión al cargar grupos.</td></tr>`;
    }
}

function useTargetInDownloader(targetId, isForum) {
    if (isForum) {
        document.getElementById("input-forum-target").value = targetId;
        switchTab("forum");
        loadAndPreAnalyzeTopics();
    } else {
        document.getElementById("input-target-url").value = targetId;
        switchTab("downloader");
    }
}

async function runOsintInspect() {
    const target = document.getElementById("input-osint-info-target").value.trim();
    if (!target) return alert("Ingresa un objetivo.");
    const out = document.getElementById("osint-info-output");
    out.innerText = "Consultando metadatos...";
    out.classList.remove("hidden");

    try {
        const res = await fetch(`${API_BASE}/osint/inspect`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ target })
        });
        const data = await res.json();
        out.innerHTML = `<pre class="text-cyan-400">${JSON.stringify(data, null, 2)}</pre>`;
    } catch (e) {
        out.innerText = "Error ejecutando consulta OSINT.";
    }
}

async function runOsintStats() {
    const target = document.getElementById("input-osint-stats-target").value.trim();
    if (!target) return alert("Ingresa un canal o grupo.");
    const out = document.getElementById("osint-stats-output");
    out.innerText = "Analizando mensajes y calculando horarios pico...";
    out.classList.remove("hidden");

    try {
        const res = await fetch(`${API_BASE}/osint/stats`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ target })
        });
        const data = await res.json();
        out.innerHTML = `<pre class="text-[#00FF41]">${JSON.stringify(data, null, 2)}</pre>`;
    } catch (e) {
        out.innerText = "Error ejecutando análisis de estadísticas.";
    }
}

async function runOsintKeywordSearch() {
    const target = document.getElementById("input-osint-search-target").value.trim();
    const keyword = document.getElementById("input-osint-search-keyword").value.trim();
    if (!target || !keyword) return alert("Ingresa el canal y la palabra clave.");

    const out = document.getElementById("osint-search-output");
    out.innerText = "Buscando mensajes...";
    out.classList.remove("hidden");

    try {
        const res = await fetch(`${API_BASE}/osint/search-keywords`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ target, keyword, limit: 50 })
        });
        const data = await res.json();
        out.innerHTML = `<pre class="text-[#FFE600]">${JSON.stringify(data, null, 2)}</pre>`;
    } catch (e) {
        out.innerText = "Error en búsqueda de palabras clave.";
    }
}

async function runOsintRecent() {
    const target = document.getElementById("input-osint-recent-target").value.trim();
    if (!target) return alert("Ingresa el canal o grupo.");

    const out = document.getElementById("osint-recent-output");
    out.innerText = "Obteniendo últimos mensajes...";
    out.classList.remove("hidden");

    try {
        const res = await fetch(`${API_BASE}/osint/recent`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ target, limit: 15 })
        });
        const data = await res.json();
        out.innerHTML = `<pre class="text-cyan-300">${JSON.stringify(data, null, 2)}</pre>`;
    } catch (e) {
        out.innerText = "Error obteniendo mensajes recientes.";
    }
}

// -------------------------------------------------------------
// PESTAÑA 5: DEDUPLICACIÓN SHA-256
// -------------------------------------------------------------
async function loadDedupStats() {
    try {
        const res = await fetch(`${API_BASE}/jobs/stats/dedup`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        const data = await res.json();
        if (res.ok) {
            document.getElementById("dedup-stat-unique-files").innerText = data.unique_files || 0;
            document.getElementById("dedup-stat-skipped-files").innerText = data.skipped_files || 0;
            document.getElementById("dedup-stat-saved-mb").innerText = `${data.saved_mb || 0} MB`;
            document.getElementById("dedup-stat-ratio").innerText = `${data.dedup_ratio_pct || 0}%`;
        }
    } catch (e) {}
}

// -------------------------------------------------------------
// MODAL LOGIN TELEGRAM
// -------------------------------------------------------------
function openTelegramModal() {
    document.getElementById("modal-telegram").classList.remove("hidden");
    document.getElementById("tg-step-phone").classList.remove("hidden");
    document.getElementById("tg-step-code").classList.add("hidden");
    document.getElementById("tg-modal-status").classList.add("hidden");
}

function closeTelegramModal() {
    document.getElementById("modal-telegram").classList.add("hidden");
}

async function submitTelegramPhone() {
    const phone = document.getElementById("tg-phone-input").value.trim();
    if (!phone) return alert("Ingresa tu número de teléfono.");

    const statusBox = document.getElementById("tg-modal-status");
    statusBox.innerText = "Enviando código...";
    statusBox.className = "text-xs mt-3 text-center text-cyan-400 block";

    try {
        const res = await fetch(`${API_BASE}/telegram/send-code`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ phone })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error enviando código");

        document.getElementById("tg-step-phone").classList.add("hidden");
        document.getElementById("tg-step-code").classList.remove("hidden");
        statusBox.innerText = data.message;
        statusBox.className = "text-xs mt-3 text-center text-emerald-400 block";
    } catch (err) {
        statusBox.innerText = err.message;
        statusBox.className = "text-xs mt-3 text-center text-red-400 block";
    }
}

async function submitTelegramCode() {
    const phone = document.getElementById("tg-phone-input").value.trim();
    const code = document.getElementById("tg-code-input").value.trim();
    const password = document.getElementById("tg-2fa-input").value;
    const statusBox = document.getElementById("tg-modal-status");

    try {
        const res = await fetch(`${API_BASE}/telegram/verify-code`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ phone, code, password: password || null })
        });
        const data = await res.json();
        if (!res.ok) {
            if (data.detail && data.detail.includes("2FA")) {
                document.getElementById("tg-2fa-box").classList.remove("hidden");
                throw new Error("Ingresa tu contraseña de verificación en dos pasos (2FA).");
            }
            throw new Error(data.detail || "Error verificando código");
        }

        statusBox.innerText = data.message;
        statusBox.className = "text-xs mt-3 text-center text-emerald-400 block";
        setTimeout(() => {
            closeTelegramModal();
            initApp();
        }, 1500);

    } catch (err) {
        statusBox.innerText = err.message;
        statusBox.className = "text-xs mt-3 text-center text-red-400 block";
    }
}

async function disconnectTelegram() {
    if (!confirm("¿Deseas desconectar tu cuenta de Telegram?")) return;
    await fetch(`${API_BASE}/telegram/disconnect`, {
        method: "DELETE",
        headers: { "Authorization": `Bearer ${token}` }
    });
    initApp();
}

async function connectGoogleDrive() {
    try {
        const res = await fetch(`${API_BASE}/drive/auth-url`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        const data = await res.json();
        if (data.auth_url) {
            window.open(data.auth_url, "_blank");
        } else {
            alert(data.detail || "Configura las credenciales de Google OAuth en el backend.");
        }
    } catch (e) {
        alert("Error al conectar con Google Drive.");
    }
}

async function disconnectDrive() {
    if (!confirm("¿Deseas desconectar Google Drive?")) return;
    await fetch(`${API_BASE}/drive/disconnect`, {
        method: "DELETE",
        headers: { "Authorization": `Bearer ${token}` }
    });
    initApp();
}

// -------------------------------------------------------------
// PESTAÑA 6: BUSCADOR GLOBAL TELEGRAM EN VIVO & DESCARGA EN ZIP
// -------------------------------------------------------------
let currentTelegramSearchResults = [];

async function runTelegramGlobalSearch() {
    const qInput = document.getElementById("input-tg-global-search");
    const q = qInput ? qInput.value.trim() : "";
    if (!q) {
        alert("Por favor ingresa un término o palabra clave a buscar (ej: GOROSO, Maca Escudero, etc.).");
        return;
    }

    const filterEl = document.getElementById("select-tg-search-filter");
    const filter = filterEl ? filterEl.value : "ALL";
    const tbody = document.getElementById("tbody-tg-search-results");
    const loadingEl = document.getElementById("tg-search-loading");
    const summaryBox = document.getElementById("tg-search-summary-box");
    const btnSearch = document.getElementById("btn-run-tg-search");

    if (loadingEl) loadingEl.classList.remove("hidden");
    if (summaryBox) summaryBox.classList.add("hidden");
    if (btnSearch) btnSearch.disabled = true;

    try {
        const res = await fetch(`${API_BASE}/osint/telegram-global-search`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                query: q,
                media_filter: filter,
                limit: 150
            })
        });

        const data = await res.json();
        if (loadingEl) loadingEl.classList.add("hidden");
        if (btnSearch) btnSearch.disabled = false;

        if (!res.ok) {
            alert(data.detail || "Error al realizar la búsqueda en Telegram.");
            return;
        }

        currentTelegramSearchResults = data.results || [];
        const summary = data.summary || {};

        document.getElementById("tg-search-stat-total").innerText = summary.total_matches || 0;
        document.getElementById("tg-search-stat-videos").innerText = summary.videos_count || 0;
        document.getElementById("tg-search-stat-photos").innerText = summary.photos_count || 0;
        document.getElementById("tg-search-stat-mb").innerText = `${summary.total_mb || 0} MB`;

        if (summaryBox) summaryBox.classList.remove("hidden");

        if (!currentTelegramSearchResults || currentTelegramSearchResults.length === 0) {
            if (tbody) {
                tbody.innerHTML = `<tr><td colspan="6" class="text-center text-slate-500 py-8">No se encontraron mensajes o archivos con el término "${q}" en tus chats de Telegram.</td></tr>`;
            }
            return;
        }

        if (tbody) {
            tbody.innerHTML = currentTelegramSearchResults.map((r, idx) => {
                const isMedia = r.has_media;
                const typeBadge = r.media_type === "VIDEO" ? '<span class="px-2 py-0.5 rounded bg-emerald-500/20 text-[#00FF41] border border-emerald-500/30 text-xs font-bold">Video 🎥</span>' :
                                  (r.media_type === "PHOTO" ? '<span class="px-2 py-0.5 rounded bg-sky-500/20 text-[#00F0FF] border border-sky-500/30 text-xs font-bold">Foto 📷</span>' :
                                  (r.media_type === "DOCUMENT" ? '<span class="px-2 py-0.5 rounded bg-yellow-500/20 text-[#FFE600] border border-yellow-500/30 text-xs font-bold">Doc 📄</span>' :
                                  '<span class="px-2 py-0.5 rounded bg-slate-800 text-slate-400 text-xs">Texto</span>'));

                let originBadge = "";
                if (r.origin === "FORUM_TOPIC") {
                    originBadge = '<span class="px-1.5 py-0.5 rounded bg-blue-500/20 text-blue-300 border border-blue-500/30 text-[10px] font-mono ml-1">TOPIC</span>';
                } else if (r.origin === "ALBUM_PACK") {
                    originBadge = '<span class="px-1.5 py-0.5 rounded bg-purple-500/20 text-purple-300 border border-purple-500/30 text-[10px] font-mono ml-1">ÁLBUM</span>';
                } else if (r.origin === "CONTEXT_ADJACENT") {
                    originBadge = '<span class="px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30 text-[10px] font-mono ml-1">MENCIÓN</span>';
                }

                return `
                    <tr class="hover:bg-slate-900/50 transition">
                        <td class="text-center">
                            ${isMedia ? `<input type="checkbox" value="${idx}" class="tg-result-checkbox w-4 h-4 rounded border-slate-700 bg-slate-900 text-cyan-500" checked>` : `<span class="text-slate-600">-</span>`}
                        </td>
                        <td class="font-semibold text-cyan-300 text-xs max-w-[180px] truncate" title="${r.chat_title}">
                            📁 ${r.chat_title} ${originBadge}
                        </td>
                        <td class="text-xs text-slate-200 max-w-xs truncate" title="${r.text || ''}">
                            ${r.text ? r.text : '<span class="italic text-slate-500">[Archivo Multimedia Adjunto]</span>'}
                        </td>
                        <td class="text-xs text-slate-400">
                            <span class="text-slate-300 block font-semibold truncate">${r.sender_name}</span>
                            <span class="text-[11px] text-slate-500 font-mono">${r.date}</span>
                        </td>
                        <td class="text-center text-xs whitespace-nowrap">
                            ${typeBadge}
                            ${r.size_mb > 0 ? `<span class="font-mono text-[#FFE600] ml-1.5 font-bold">${r.size_mb} MB</span>` : ''}
                        </td>
                        <td class="text-right">
                            ${isMedia ? `
                                <a href="${API_BASE}/osint/download-single-media?chat_id=${r.chat_id}&msg_id=${r.msg_id}&token=${token}" target="_blank" class="px-2.5 py-1 rounded bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 border border-cyan-500/30 text-xs font-bold inline-flex items-center gap-1 transition">
                                    <i class="fa-solid fa-download"></i> Descargar
                                </a>
                            ` : `<span class="text-slate-600 text-xs">Solo Texto</span>`}
                        </td>
                    </tr>
                `;
            }).join("");
        }

    } catch (err) {
        if (loadingEl) loadingEl.classList.add("hidden");
        if (btnSearch) btnSearch.disabled = false;
        alert("Error de conexión al buscar en Telegram.");
    }
}

function toggleSelectAllTgResults(checked) {
    const checkboxes = document.querySelectorAll(".tg-result-checkbox");
    checkboxes.forEach(cb => cb.checked = checked);
}

async function downloadSelectedTelegramSearchResultsZip() {
    const checkboxes = document.querySelectorAll(".tg-result-checkbox:checked");
    if (checkboxes.length === 0) {
        alert("Selecciona al menos un archivo multimedia de los resultados para descargar.");
        return;
    }

    const selectedIndices = Array.from(checkboxes).map(cb => parseInt(cb.value));
    const selectedItems = selectedIndices.map(i => currentTelegramSearchResults[i]).filter(Boolean);
    await startTelegramSearchBatchJob(selectedItems);
}

async function downloadAllTelegramSearchResultsZip() {
    const mediaItems = currentTelegramSearchResults.filter(r => r.has_media);
    if (mediaItems.length === 0) {
        alert("No hay archivos multimedia en los resultados de búsqueda para empaquetar en ZIP.");
        return;
    }
    await startTelegramSearchBatchJob(mediaItems);
}

async function startTelegramSearchBatchJob(items) {
    const qInput = document.getElementById("input-tg-global-search");
    const q = qInput ? qInput.value.trim() : "Busqueda";

    try {
        const res = await fetch(`${API_BASE}/osint/download-search-batch`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                query: q,
                selected_items: items.map(it => ({
                    chat_id: it.chat_id,
                    msg_id: it.msg_id,
                    chat_title: it.chat_title
                })),
                destination: "DIRECT_DOWNLOAD",
                concurrency: 10
            })
        });

        const data = await res.json();
        if (!res.ok) {
            alert(data.detail || "Error al iniciar la descarga masiva en ZIP.");
            return;
        }

        activeJobId = data.job_id;
        switchTab("jobs");
        handleLiveProgress({
            job_id: data.job_id,
            status: "INICIANDO",
            progress: 0,
            speed_mbs: 0,
            eta_seconds: 0
        });

    } catch (err) {
        alert("Error al conectar con el servidor para iniciar la descarga.");
    }
}



