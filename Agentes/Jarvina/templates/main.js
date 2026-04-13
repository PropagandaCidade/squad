/**
 * main.js — V5 (Definitivo)
 * - VU meter sempre (preview do mic)
 * - Envia áudio PCM 16kHz pro Railway quando wsReady=true
 * - Só envia end_of_turn se houver bytes enviados desde o último EOT
 * - Mostra HUD: PCM ON/OFF + bytes enviados + retorno do backend (mic_debug)
 *
 * Requisitos:
 * - media-handler.js V4 (PCM WORKLET: ON)
 * - gemini-client.js com sendRealtimeChunk() e sendEndOfTurn()
 */

document.addEventListener("DOMContentLoaded", () => {
  // UI
  const btn = document.getElementById("live-btn");
  const statusText = document.getElementById("status-text");
  const responseArea = document.getElementById("main-display");
  const transcriptArea = document.getElementById("user-transcript");

  // VU UI
  const vuFill = document.getElementById("vu-fill");
  const vuDot = document.getElementById("vu-dot");
  const micOk = document.getElementById("mic-ok");
  const telemetryMic = document.getElementById("telemetry-mic");
  const telemetryBytes = document.getElementById("telemetry-bytes");
  const telemetryChunks = document.getElementById("telemetry-chunks");
  const telemetryModel = document.getElementById("telemetry-model");

  const RAILWAY_WS_URL = "wss://jarvina-production.up.railway.app/ws/live";
  const configWsUrl =
    typeof window.JARVINA_CONFIG?.wsUrl === "string"
      ? window.JARVINA_CONFIG.wsUrl.trim()
      : "";
  const LIVE_WS_URL = /^wss?:\/\//i.test(configWsUrl) ? configWsUrl : RAILWAY_WS_URL;

  const media = new MediaHandler();
  const client = new GeminiClient(LIVE_WS_URL);

  // states
  let micReady = false;
  let wsReady = false;
  let isConnecting = false;
  let isLive = false;

  // VU smoothing
  let vuSmooth = 0;
  let lastVuPaintAt = 0;

  // EOT gating
  let lastEndOfTurnAt = 0;
  let sentBytesSinceLastEOT = 0;

  // stats / debug
  let sentBytesTotal = 0;
  let sentChunksTotal = 0;
  let lastMicDebugAt = 0;
  let currentCaptureRate = 16000;
  let lastVoiceDetectedAt = 0;
  let welcomeSpoken = false;
  let manualCloseRequested = false;
  let reconnectAttempts = 0;
  let reconnectTimer = null;
  let lastConnectAt = 0;
  let backendMicBytes = 0;
  let backendMicChunks = 0;
  let lastModelEventAt = 0;
  let lastForcedEndOfTurnAt = 0;
  let fallbackTurnTimer = null;
  let turnOpenAt = 0;
  let awaitingModelResponse = false;
  let endOfTurnLock = false;
  const recentAudioChunkKeys = new Map();
  let lastUserTurnText = "";
  let lastMemorySetName = "";

  function setStatus(text) {
    if (statusText) statusText.innerText = text;
  }

  function setLiveUI(on) {
    isLive = on;
    if (typeof window.updateUI === "function") window.updateUI(on);
  }

  function clamp(n, min, max) {
    return Math.max(min, Math.min(max, n));
  }

  function energyToPercent(energy) {
    const e = clamp(energy || 0, 0, 0.05);
    const normalized = e / 0.05;
    const curved = Math.pow(normalized, 0.65);
    return clamp(curved * 100, 0, 100);
  }

  function paintVU(energy) {
    if (!vuFill || !vuDot) return;

    const now = performance.now();
    if (now - lastVuPaintAt < 33) return;
    lastVuPaintAt = now;

    const target = energyToPercent(energy);

    // smoothing
    const up = 0.35;
    const down = 0.12;
    if (target > vuSmooth) vuSmooth = vuSmooth + (target - vuSmooth) * up;
    else vuSmooth = vuSmooth + (target - vuSmooth) * down;

    vuFill.style.width = `${vuSmooth.toFixed(1)}%`;

    if (vuSmooth > 6) vuDot.classList.add("on");
    else vuDot.classList.remove("on");
  }

  function setMicOkText(text) {
    if (!micOk) return;
    micOk.innerText = text;
  }

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }

  function setTelemetry({ mic, bytes, chunks, model } = {}) {
    if (telemetryMic && typeof mic === "string") telemetryMic.innerText = mic;
    if (telemetryBytes && Number.isFinite(bytes)) telemetryBytes.innerText = formatBytes(bytes);
    if (telemetryChunks && Number.isFinite(chunks)) telemetryChunks.innerText = String(chunks);
    if (telemetryModel && typeof model === "string") telemetryModel.innerText = model;
  }

  function markModelActivity() {
    lastModelEventAt = Date.now();
    awaitingModelResponse = false;
    endOfTurnLock = false;
  }

  function buildAudioChunkKey(data, mime) {
    if (!data || typeof data !== "string") return null;
    const head = data.slice(0, 48);
    const tail = data.slice(-48);
    return `${mime || "audio/pcm"}:${data.length}:${head}:${tail}`;
  }

  function shouldPlayAudioChunk(data, mime) {
    const now = Date.now();
    const ttlMs = 15000;
    for (const [key, ts] of recentAudioChunkKeys.entries()) {
      if (now - ts > ttlMs) recentAudioChunkKeys.delete(key);
    }

    const key = buildAudioChunkKey(data, mime);
    if (!key) return false;
    if (recentAudioChunkKeys.has(key)) return false;
    recentAudioChunkKeys.set(key, now);
    return true;
  }

  function sendEndOfTurnSafely(modelLabel = "AGUARDANDO RESPOSTA") {
    if (!wsReady) return false;
    if (sentBytesSinceLastEOT <= 0) return false;
    if (endOfTurnLock) return false;

    const now = Date.now();
    const minGapMs = 350;
    const responseWaitGapMs = 3800;

    if (now - lastEndOfTurnAt < minGapMs) return false;
    if (awaitingModelResponse && now - lastEndOfTurnAt < responseWaitGapMs) return false;

    try {
      client.sendEndOfTurn();
      lastEndOfTurnAt = now;
      sentBytesSinceLastEOT = 0;
      turnOpenAt = 0;
      lastForcedEndOfTurnAt = now;
      awaitingModelResponse = true;
      endOfTurnLock = true;
      setTelemetry({ model: modelLabel });
      return true;
    } catch (_) {
      return false;
    }
  }

  function normalizePreferredName(raw) {
    if (typeof raw !== "string") return "";
    let value = raw.trim().replace(/^["'`´“”‘’]+|["'`´“”‘’]+$/g, "");
    value = value.replace(/[,.;!?].*$/, "").trim();
    if (value.length < 2) return "";
    if (value.length > 60) value = value.slice(0, 60).trim();
    if (!/^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9._' -]*$/.test(value)) return "";
    return value;
  }

  function extractPreferredNameFromText(text) {
    if (typeof text !== "string") return "";
    const patterns = [
      /\b(?:me\s+cham(?:e|a)|pode\s+me\s+chamar|quero\s+que\s+me\s+chame|me\s+chame\s+sempre)\s+de\s+(.+)$/i,
      /\bmeu\s+nome\s+(?:é|e)\s+(.+)$/i
    ];
    for (const pattern of patterns) {
      const match = text.match(pattern);
      if (!match) continue;
      const normalized = normalizePreferredName(match[1] || "");
      if (normalized) return normalized;
    }
    return "";
  }

  function resolveOpenPageTarget(rawPath) {
    if (typeof rawPath !== "string") return "";
    const candidate = rawPath.trim().replace(/^["'`´“”‘’]+|["'`´“”‘’]+$/g, "");
    if (!candidate) return "";

    if (/^https?:\/\//i.test(candidate)) return candidate;
    if (!/^[A-Za-z0-9_./-]+$/.test(candidate)) return "";

    let normalized = candidate;
    if (normalized.startsWith("./")) normalized = normalized.slice(2);
    if (normalized.startsWith("/")) return normalized;
    return `/${normalized}`;
  }

  function extractOpenPageFromText(text) {
    if (typeof text !== "string") return "";
    const match = text.match(/\b(?:abra|abrir|abre)\s+(?:a\s+)?(?:p[aá]gina|arquivo)?\s*([A-Za-z0-9_./-]+\.(?:html?|php))\b/i);
    if (!match) return "";
    return resolveOpenPageTarget(match[1] || "");
  }

  function resetTelemetry() {
    backendMicBytes = 0;
    backendMicChunks = 0;
    setTelemetry({
      mic: wsReady ? "AGUARDANDO" : "STANDBY",
      bytes: 0,
      chunks: 0,
      model: "AGUARDANDO",
    });
  }

  function speakAssistantText(text) {
    if (!text || typeof text !== "string") return;
    if (!("speechSynthesis" in window) || typeof SpeechSynthesisUtterance === "undefined") return;

    try {
      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = "pt-BR";
      utterance.rate = 1;
      utterance.pitch = 1;
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(utterance);
    } catch (_) {}
  }

  function getSessionAdminToken() {
    const rawToken =
      typeof window.JARVINA_CONFIG?.adminToken === "string"
        ? window.JARVINA_CONFIG.adminToken.trim()
        : "";

    if (!rawToken) return null;
    if (rawToken.length > 128) return null;
    return rawToken;
  }

  function preferredNameStorageKey(adminToken) {
    return `jarvina.preferred_name.${adminToken}`;
  }

  function getStoredPreferredName(adminToken) {
    if (!adminToken) return "";
    try {
      const raw = window.localStorage.getItem(preferredNameStorageKey(adminToken));
      return normalizePreferredName(raw || "");
    } catch (_) {
      return "";
    }
  }

  function persistPreferredName(adminToken, preferredName) {
    if (!adminToken) return;
    const normalized = normalizePreferredName(preferredName);
    if (!normalized) return;
    try {
      window.localStorage.setItem(preferredNameStorageKey(adminToken), normalized);
    } catch (_) {}
  }

  function arrayBufferToBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
    }
    return btoa(binary);
  }

  function resamplePcm16(buffer, sourceRate, targetRate = 16000) {
    if (!buffer) return buffer;
    if (!Number.isFinite(sourceRate) || !Number.isFinite(targetRate) || sourceRate <= 0 || targetRate <= 0) {
      return buffer;
    }
    if (Math.round(sourceRate) === Math.round(targetRate)) return buffer;

    const source = new Int16Array(buffer);
    if (!source.length) return buffer;

    const ratio = sourceRate / targetRate;
    const targetLength = Math.max(1, Math.floor(source.length / ratio));
    const target = new Int16Array(targetLength);

    for (let i = 0; i < targetLength; i++) {
      const pos = i * ratio;
      const left = Math.floor(pos);
      const right = Math.min(left + 1, source.length - 1);
      const frac = pos - left;
      const sample = source[left] + (source[right] - source[left]) * frac;
      target[i] = Math.max(-32768, Math.min(32767, Math.round(sample)));
    }

    return target.buffer;
  }

  function parseRateFromMime(mime) {
    if (!mime || typeof mime !== "string") return null;
    const m = mime.match(/rate\s*=\s*(\d+)/i);
    if (!m) return null;
    const r = parseInt(m[1], 10);
    return Number.isFinite(r) ? r : null;
  }

  function base64ToArrayBuffer(b64) {
    const binaryString = atob(b64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) bytes[i] = binaryString.charCodeAt(i);
    return bytes.buffer;
  }

  function updateHud({ pcmOk } = {}) {
    const pcmStatus = pcmOk === true ? "PCM: ON" : (pcmOk === false ? "PCM: OFF" : "PCM: ?");
    const net = wsReady ? "LIVE: ON" : "LIVE: OFF";
    const sent = `SENT: ${(sentBytesTotal / 1024).toFixed(1)}KB`;
    const rate = `RATE: ${currentCaptureRate}Hz->16000Hz`;
    setMicOkText(`${pcmStatus} • ${net} • ${rate} • ${sent}`);
  }

  async function startMicPreview() {
    try {
      setStatus("Mic: pedindo permissão...");
      if (responseArea) responseArea.innerText = "Ative o microfone do navegador. O medidor deve mexer ao falar.";
      updateHud({ pcmOk: media.getPcmStatus ? media.getPcmStatus() : undefined });
      resetTelemetry();

      await media.init(({ pcmBuffer, energy, isSpeaking, endOfTurn, pcmOk, sampleRate }) => {
        paintVU(energy);
        if (Number.isFinite(sampleRate) && sampleRate >= 8000 && sampleRate <= 96000) {
          currentCaptureRate = Math.round(sampleRate);
        }
        if (Number.isFinite(energy) && energy >= 0.006) {
          lastVoiceDetectedAt = Date.now();
        }

        if (!micReady) {
          micReady = true;
          setStatus("Mic: OK (preview)");
          if (responseArea) responseArea.innerText = "Microfone OK ✅ Agora clique em CONEXÃO LIVE para falar com a Jarvina.";
          setTelemetry({ mic: "PRONTO" });
        }

        updateHud({ pcmOk });

        // Se NÃO está conectado ao WS, não envia nada
        if (!wsReady) return;

        // Só envia áudio quando o VAD confirma fala e o playback do modelo não está ativo.
        let playbackActive = typeof media.isPlaybackActive === "function" && media.isPlaybackActive();
        const interruptByVoice = playbackActive && Number.isFinite(energy) && energy >= 0.03;
        if (interruptByVoice) {
          if (typeof media.stopPlayback === "function") {
            media.stopPlayback();
          }
          endOfTurnLock = false;
          awaitingModelResponse = false;
        }

        playbackActive = typeof media.isPlaybackActive === "function" && media.isPlaybackActive();
        const shouldSendAudio = !!pcmBuffer && isSpeaking && !playbackActive;

        if (shouldSendAudio) {
          const streamRate = 16000;
          const pcmToSend = resamplePcm16(pcmBuffer, currentCaptureRate, streamRate);
          const b64 = arrayBufferToBase64(pcmToSend);
          client.sendRealtimeChunk({ data: b64, mime_type: `audio/pcm;rate=${streamRate}` }, false);
          if (turnOpenAt === 0) turnOpenAt = Date.now();

          // stats
          const bytes = pcmToSend.byteLength || 0;
          sentBytesTotal += bytes;
          sentBytesSinceLastEOT += bytes;
          sentChunksTotal += 1;
        }

        // ✅ Só envia EOT se já enviou áudio desde o último EOT
        if (endOfTurn) {
          sendEndOfTurnSafely("AGUARDANDO RESPOSTA");
        } else if (lastVoiceDetectedAt > 0 && sentBytesSinceLastEOT > 4096) {
          const now = Date.now();
          const silenceMs = now - lastVoiceDetectedAt;
          if (silenceMs > 1300 && (now - lastEndOfTurnAt) > 900) {
            sendEndOfTurnSafely("AGUARDANDO RESPOSTA");
          }
        }
      });

      // VAD
      media.setVadConfig({
        enabled: true,
        threshold: 0.010,
        speechHangMs: 420,
        minSpeechMs: 220
      });
      media.setDuckWhilePlaying(true);

    } catch (e) {
      console.error("Mic preview falhou:", e);
      setStatus("Mic: falhou");
      setMicOkText("MIC: bloqueado");
      setTelemetry({ mic: "BLOQUEADO", model: "OFFLINE" });
      if (responseArea) responseArea.innerText =
        "Não consegui acessar o microfone. Verifique permissões do navegador e se está em HTTPS.";
    }
  }

  async function connectLive() {
    if (isConnecting || isLive) return;
    isConnecting = true;
    manualCloseRequested = false;
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    lastConnectAt = Date.now();

    try {
      setStatus("Conectando...");
      if (responseArea) responseArea.innerText = "Abrindo link neural...";
      if (transcriptArea) transcriptArea.innerText = "";
      setTelemetry({ mic: "CONECTANDO", model: "AGUARDANDO", bytes: 0, chunks: 0 });

      const adminToken = getSessionAdminToken();
      if (!adminToken) {
        wsReady = false;
        isLive = false;
        setLiveUI(false);
        setStatus("Sessao invalida");
        setMicOkText("LIVE: OFF • AUTH: invalida");
        setTelemetry({ mic: "SESSAO INVALIDA", model: "OFFLINE" });
        if (responseArea) {
          responseArea.innerText =
            "Sessao admin invalida. Reabra a Jarvina pelo painel para conectar.";
        }
        return;
      }

      const storedPreferredName = getStoredPreferredName(adminToken);
      await client.connect(adminToken, storedPreferredName || "");
      if (storedPreferredName) {
        lastMemorySetName = storedPreferredName.toLowerCase();
      }
      wsReady = true;
      isLive = true;
      setLiveUI(true);
      sentBytesSinceLastEOT = 0;
      lastEndOfTurnAt = 0;
      lastVoiceDetectedAt = 0;
      welcomeSpoken = false;
      backendMicBytes = 0;
      backendMicChunks = 0;
      lastModelEventAt = Date.now();
      lastForcedEndOfTurnAt = 0;
      turnOpenAt = 0;
      awaitingModelResponse = false;
      endOfTurnLock = false;
      recentAudioChunkKeys.clear();
      lastUserTurnText = "";
      if (fallbackTurnTimer) {
        clearInterval(fallbackTurnTimer);
        fallbackTurnTimer = null;
      }

      setStatus("Jarvina ao vivo");
      if (responseArea) responseArea.innerText = "Fale normalmente — Jarvina está ouvindo.";
      setMicOkText("LIVE: ON • OUVINDO");
      setTelemetry({ mic: "OUVINDO", model: "AGUARDANDO", bytes: 0, chunks: 0 });

      fallbackTurnTimer = setInterval(() => {
        if (!isLive || !wsReady) return;
        const now = Date.now();
        const hasLocalAudioPending = sentBytesSinceLastEOT > 2048;
        const isSilent = lastVoiceDetectedAt > 0 && (now - lastVoiceDetectedAt) > 1800;
        const waitingModel = (now - lastModelEventAt) > 2200;
        const recentlyForced = (now - lastForcedEndOfTurnAt) < 2500;
        const turnOpenTooLong = turnOpenAt > 0 && (now - turnOpenAt) > 6500;

        if (hasLocalAudioPending && waitingModel && !recentlyForced && !awaitingModelResponse && !endOfTurnLock && (isSilent || turnOpenTooLong)) {
          sendEndOfTurnSafely(turnOpenTooLong ? "FORCANDO TURNO" : "AGUARDANDO RESPOSTA");
        }
      }, 700);

      client.onMessageCallback = (data) => {
        if (data && data.type === "error") {
          const text = data.text || "Falha de autorizacao da sessao.";
          setStatus("Erro de autenticacao");
          if (responseArea) responseArea.innerText = text;
          setTelemetry({ mic: "ERRO", model: "ERRO" });
          stopLive(text);
          return;
        }

        // ✅ Confirma recebimento no backend
        if (data && data.type === "mic_debug") {
          lastMicDebugAt = Date.now();
          const bytes = Number.isFinite(data.bytes) ? data.bytes : 0;
          const chunks = Number.isFinite(data.chunks) ? data.chunks : 0;
          backendMicBytes = bytes;
          backendMicChunks = chunks;
          if (bytes > 0 || chunks > 0) {
            reconnectAttempts = 0;
          }
          const eot = data.end_of_turn ? " | EOT ✅" : "";
          const pcmStatus = media.getPcmStatus ? (media.getPcmStatus() ? "PCM: ON" : "PCM: OFF") : "PCM:?";
          setMicOkText(`${pcmStatus} • LIVE: ON • MIC OK: ${chunks}/${bytes}${eot}`);
          setTelemetry({
            mic: bytes > 0 ? "OK" : "SEM DADOS",
            bytes,
            chunks,
          });
          return;
        }

        // welcome
        if (data && data.type === "welcome") {
          const welcomeText = data.text || "Conectado.";
          if (responseArea) responseArea.innerText = welcomeText;
          welcomeSpoken = true;
          markModelActivity();
          setTelemetry({ model: "SESSAO ON" });
          return;
        }

        if (data && data.type === "memory_update" && data.scope === "preferred_name") {
          const preferredName = typeof data.value === "string" ? data.value.trim() : "";
          if (preferredName && responseArea) {
            responseArea.innerText = `Memoria atualizada. Vou te chamar de ${preferredName}.`;
            lastMemorySetName = preferredName.toLowerCase();
            const adminToken = getSessionAdminToken();
            if (adminToken) persistPreferredName(adminToken, preferredName);
          }
          return;
        }

        const serverContent = data?.serverContent || data?.server_content;

        const modelTurn = serverContent?.modelTurn || serverContent?.model_turn;
        const userTurn =
          serverContent?.userTurn ||
          serverContent?.user_turn ||
          data?.userTurn ||
          data?.user_turn;

        if (!modelTurn && !userTurn) return;

        if (modelTurn?.parts) {
          let sawModelAudio = false;
          let sawModelText = false;
          modelTurn.parts.forEach((part) => {
            const inline = part.inlineData || part.inline_data;

            if (inline?.data) {
              const mime = inline.mimeType || inline.mime_type || "";
              if (shouldPlayAudioChunk(inline.data, mime)) {
                const pcmBuffer = base64ToArrayBuffer(inline.data);
                const rate = parseRateFromMime(mime) || 24000;
                media.playAudioChunk(pcmBuffer, rate);
                sawModelAudio = true;
              }
            }

            if (part.text) {
              if (responseArea) responseArea.innerText = part.text;
              sawModelText = true;
            }
          });

          if (sawModelAudio || sawModelText) {
            markModelActivity();
            const mode = sawModelAudio && sawModelText
              ? "OK AUDIO+TEXTO"
              : sawModelAudio
                ? "OK AUDIO"
                : "OK TEXTO";
            setTelemetry({ model: mode });
          }
        }

        if (userTurn?.parts?.[0]?.text && transcriptArea) {
          const userText = String(userTurn.parts[0].text || "").trim();
          transcriptArea.innerText = `"${userText}"`;

          if (userText && userText !== lastUserTurnText) {
            lastUserTurnText = userText;

            const preferredName = extractPreferredNameFromText(userText);
            if (preferredName) {
              const preferredKey = preferredName.toLowerCase();
              if (preferredKey !== lastMemorySetName) {
                client.sendMemorySet(preferredName);
                lastMemorySetName = preferredKey;
                const adminToken = getSessionAdminToken();
                if (adminToken) persistPreferredName(adminToken, preferredName);
              }
            }

            const openTarget = extractOpenPageFromText(userText);
            if (openTarget) {
              if (responseArea) responseArea.innerText = `Abrindo ${openTarget}...`;
              setTimeout(() => {
                window.location.href = openTarget;
              }, 250);
            }
          }
        }
      };

      if (typeof client.drainPendingMessages === "function") {
        client.drainPendingMessages();
      }

      client.onCloseCallback = (ev) => {
        if (fallbackTurnTimer) {
          clearInterval(fallbackTurnTimer);
          fallbackTurnTimer = null;
        }
        const code = ev && Number.isFinite(ev.code) ? ev.code : null;
        const reason = ev && typeof ev.reason === "string" ? ev.reason.trim() : "";
        const closedQuickly = (Date.now() - lastConnectAt) < 7000;

        if (!manualCloseRequested && closedQuickly && reconnectAttempts < 2 && code === 1011) {
          reconnectAttempts += 1;
          wsReady = false;
          isLive = false;
          setLiveUI(false);
          setStatus("Reconectando...");
          if (responseArea) responseArea.innerText = `Reconectando live (${reconnectAttempts}/2)...`;
          if (reconnectTimer) clearTimeout(reconnectTimer);
          reconnectTimer = setTimeout(() => {
            connectLive();
          }, 900);
          return;
        }

        if (code === 1008) {
          const details = reason ? ` (${reason})` : "";
          stopLive(`Conexao encerrada por politica do backend${details}.`);
          return;
        }

        if (code === 1011) {
          const details = reason ? ` (${reason})` : "";
          stopLive(`Falha interna no backend live${details}.`);
          return;
        }

        if (code === 1000 && reason) {
          stopLive(`Conexao encerrada pelo backend (${reason}).`);
          return;
        }

        stopLive("Link neural encerrado.");
      };

      // watchdog: se não chegar mic_debug em 4s, avisa
      setTimeout(() => {
        if (!isLive) return;
        if (!lastMicDebugAt || (Date.now() - lastMicDebugAt) > 4000) {
          setMicOkText("LIVE: ON • MIC: sem retorno");
          setTelemetry({ mic: "SEM RETORNO", bytes: backendMicBytes, chunks: backendMicChunks });
        }
      }, 4200);

    } catch (e) {
      console.error("Conexão live falhou:", e);
      setStatus("Falha na conexão");
      if (responseArea) responseArea.innerText = "Falha ao conectar no servidor.";
      setTelemetry({ mic: "OFFLINE", model: "OFFLINE" });
      if (fallbackTurnTimer) {
        clearInterval(fallbackTurnTimer);
        fallbackTurnTimer = null;
      }
      wsReady = false;
      isLive = false;
      setLiveUI(false);
    } finally {
      isConnecting = false;
    }
  }

  function stopLive(message = "Sessão encerrada.") {
    try { client.disconnect(); } catch (_) {}
    if (fallbackTurnTimer) {
      clearInterval(fallbackTurnTimer);
      fallbackTurnTimer = null;
    }
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    reconnectAttempts = 0;
    welcomeSpoken = false;
    sentBytesSinceLastEOT = 0;
    lastEndOfTurnAt = 0;
    lastVoiceDetectedAt = 0;
    lastModelEventAt = 0;
    lastForcedEndOfTurnAt = 0;
    turnOpenAt = 0;
    awaitingModelResponse = false;
    endOfTurnLock = false;
    recentAudioChunkKeys.clear();
    lastUserTurnText = "";
    try {
      if ("speechSynthesis" in window) window.speechSynthesis.cancel();
    } catch (_) {}
    wsReady = false;
    isLive = false;
    setLiveUI(false);
    setStatus(micReady ? "Mic: OK (preview)" : "Standby");
    if (responseArea) responseArea.innerText = message;
    if (transcriptArea) transcriptArea.innerText = "";
    updateHud({ pcmOk: media.getPcmStatus ? media.getPcmStatus() : undefined });
    resetTelemetry();
    if (micReady) setTelemetry({ mic: "PRONTO" });
  }

  // Button
  if (btn) {
    btn.onclick = () => {
      if (isLive) {
        manualCloseRequested = true;
        stopLive("Sessão encerrada.");
      }
      else connectLive();
    };
  }

  // Start preview immediately
  resetTelemetry();
  startMicPreview();
});
