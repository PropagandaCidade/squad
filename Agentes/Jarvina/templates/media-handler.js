/**
 * JARVINA MEDIA HANDLER (V4) — VU sempre + PCM real quando Worklet carrega
 *
 * O que resolve:
 * - Garante que o AudioWorklet carregue (URL absoluta + cache bust)
 * - Mantém VU meter funcionando SEMPRE (Analyser RMS)
 * - Expõe no callback: pcmOk (true/false) para a UI mostrar "PCM ON/OFF"
 *
 * Importante:
 * - Se pcmOk=false, você vai modular mas NÃO envia áudio pro Railway (só energia).
 */

class MediaHandler {
  constructor() {
    this.audioContext = null;
    this.stream = null;

    // Nodes
    this.sourceNode = null;
    this.analyser = null;
    this.analyserData = null;

    // Worklet PCM
    this.workletNode = null;
    this.silentGain = null;
    this._workletOk = false;

    // Playback
    this.nextStartTime = 0;
    this._activeSources = new Set();

    // VAD
    this.vadEnabled = true;
    this.vadThreshold = 0.010;
    this.speechHangMs = 280;
    this.minSpeechMs = 160;

    this._isSpeaking = false;
    this._speechStartAt = 0;
    this._lastVoiceAt = 0;

    // Callback
    this._onPacket = null;

    // Loops
    this._vuRaf = null;
    this._tickTimer = null;

    // RMS cache
    this._energy = 0;

    // Resume helper (browser gesture)
    this._resumeBound = null;

    // duck opcional
    this.duckWhilePlaying = false;
    this._playbackActiveUntil = 0;
  }

  setVadConfig({ enabled, threshold, speechHangMs, minSpeechMs } = {}) {
    if (typeof enabled === "boolean") this.vadEnabled = enabled;
    if (typeof threshold === "number") this.vadThreshold = threshold;
    if (typeof speechHangMs === "number") this.speechHangMs = speechHangMs;
    if (typeof minSpeechMs === "number") this.minSpeechMs = minSpeechMs;
  }

  setDuckWhilePlaying(enabled) {
    this.duckWhilePlaying = !!enabled;
  }

  getPcmStatus() {
    return !!this._workletOk;
  }

  isPlaybackActive() {
    return performance.now() < this._playbackActiveUntil;
  }

  stopPlayback() {
    if (!this.audioContext) return;

    this._playbackActiveUntil = 0;
    this.nextStartTime = this.audioContext.currentTime + 0.02;

    for (const source of this._activeSources) {
      try { source.stop(0); } catch (_) {}
      try { source.disconnect(); } catch (_) {}
    }
    this._activeSources.clear();
  }

  async init(onPacket) {
    this._onPacket = onPacket;

    // 1) Mic
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true
      }
    });

    // 2) AudioContext (não forçar sampleRate aqui — mais compatível)
    this.audioContext = new (window.AudioContext || window.webkitAudioContext)();

    try { await this.audioContext.resume(); } catch (_) {}

    // 3) Source + Analyser (VU)
    this.sourceNode = this.audioContext.createMediaStreamSource(this.stream);

    this.analyser = this.audioContext.createAnalyser();
    this.analyser.fftSize = 1024;
    this.analyser.smoothingTimeConstant = 0.85;
    this.analyserData = new Float32Array(this.analyser.fftSize);

    this.sourceNode.connect(this.analyser);

    // 4) Tenta carregar Worklet por URL absoluta + cache bust
    // Isso evita 404 silencioso e path relativo errado.
    const workletUrl = new URL(`pcm-processor.js?v=${Date.now()}`, window.location.href).toString();

    try {
      await this.audioContext.audioWorklet.addModule(workletUrl);
      this.workletNode = new AudioWorkletNode(this.audioContext, "pcm-processor");
      this._workletOk = true;
      console.log("[MediaHandler] PCM WORKLET: ON ✅", workletUrl);
    } catch (e) {
      this._workletOk = false;
      console.warn("[MediaHandler] PCM WORKLET: OFF ❌ (VU continua)", e, workletUrl);
    }

    // 5) Silent output
    this.silentGain = this.audioContext.createGain();
    this.silentGain.gain.value = 0;

    if (this._workletOk && this.workletNode) {
      // source -> worklet
      this.sourceNode.connect(this.workletNode);

      // worklet -> silent -> destination
      this.workletNode.connect(this.silentGain);
      this.silentGain.connect(this.audioContext.destination);

      // PCM do worklet
      this.workletNode.port.onmessage = (event) => {
        const data = event.data || {};
        const pcmBuffer = data.pcm || null; // ArrayBuffer Int16
        const energyFromWorklet = typeof data.energy === "number" ? data.energy : 0;
        const sampleRateFromWorklet = Number.isFinite(data.sampleRate) ? data.sampleRate : this.audioContext.sampleRate;

        const energy = energyFromWorklet > 0 ? energyFromWorklet : this._energy;
        const { endOfTurn, isSpeaking } = this._vadStep(energy);

        if (this._onPacket) {
          this._onPacket({
            pcmBuffer,
            energy,
            isSpeaking,
            endOfTurn,
            pcmOk: true,
            sampleRate: sampleRateFromWorklet
          });
        }
      };
    }

    // 6) Loop RMS (VU) — sempre roda
    const vuLoop = () => {
      if (!this.analyser || !this.analyserData) return;

      this.analyser.getFloatTimeDomainData(this.analyserData);

      let sumSq = 0;
      for (let i = 0; i < this.analyserData.length; i++) {
        const s = this.analyserData[i];
        sumSq += s * s;
      }
      const rms = Math.sqrt(sumSq / this.analyserData.length);
      this._energy = rms;

      // Se worklet OFF, ainda manda callback só pra VU mexer (sem PCM)
      if (!this._workletOk && this._onPacket) {
        const { endOfTurn, isSpeaking } = this._vadStep(rms);
        this._onPacket({
          pcmBuffer: null,
          energy: rms,
          isSpeaking,
          endOfTurn,
          pcmOk: false,
          sampleRate: this.audioContext ? this.audioContext.sampleRate : 16000
        });
      }

      this._vuRaf = requestAnimationFrame(vuLoop);
    };
    this._vuRaf = requestAnimationFrame(vuLoop);

    // 7) Auto-resume do AudioContext por gesto
    this._installAutoResume();

    // 8) Watchdog resume
    this._tickTimer = setInterval(async () => {
      if (!this.audioContext) return;
      if (this.audioContext.state === "suspended") {
        try { await this.audioContext.resume(); } catch (_) {}
      }
    }, 1200);
  }

  _installAutoResume() {
    if (!this.audioContext) return;

    const tryResume = async () => {
      if (!this.audioContext) return;
      if (this.audioContext.state !== "running") {
        try { await this.audioContext.resume(); } catch (_) {}
      }
    };

    this._resumeBound = () => { tryResume(); };

    window.addEventListener("pointerdown", this._resumeBound, { passive: true });
    window.addEventListener("keydown", this._resumeBound, { passive: true });
    window.addEventListener("touchstart", this._resumeBound, { passive: true });
  }

  _removeAutoResume() {
    if (!this._resumeBound) return;
    window.removeEventListener("pointerdown", this._resumeBound);
    window.removeEventListener("keydown", this._resumeBound);
    window.removeEventListener("touchstart", this._resumeBound);
    this._resumeBound = null;
  }

  _vadStep(energy) {
    const now = performance.now();
    let endOfTurn = false;

    if (this.duckWhilePlaying && now < this._playbackActiveUntil) {
      return { endOfTurn: false, isSpeaking: false };
    }

    if (!this.vadEnabled) return { endOfTurn: false, isSpeaking: this._isSpeaking };

    const isVoice = energy >= this.vadThreshold;

    if (isVoice) {
      this._lastVoiceAt = now;
      if (!this._isSpeaking) {
        this._isSpeaking = true;
        this._speechStartAt = now;
      }
    } else {
      if (this._isSpeaking) {
        const silenceMs = now - this._lastVoiceAt;
        const speechMs = now - this._speechStartAt;
        if (speechMs >= this.minSpeechMs && silenceMs >= this.speechHangMs) {
          this._isSpeaking = false;
          endOfTurn = true;
        }
      }
    }

    return { endOfTurn, isSpeaking: this._isSpeaking };
  }

  /**
   * Playback PCM Int16 (Gemini geralmente manda 24kHz PCM)
   */
  playAudioChunk(pcmBuffer, sampleRate = 24000) {
    if (!this.audioContext || !pcmBuffer) return;

    this._playbackActiveUntil = Math.max(this._playbackActiveUntil, performance.now() + 420);

    const pcmData = new Int16Array(pcmBuffer);
    const floatData = new Float32Array(pcmData.length);
    for (let i = 0; i < pcmData.length; i++) floatData[i] = pcmData[i] / 32768;

    const buffer = this.audioContext.createBuffer(1, floatData.length, sampleRate);
    buffer.getChannelData(0).set(floatData);

    const source = this.audioContext.createBufferSource();
    source.buffer = buffer;
    source.connect(this.audioContext.destination);
    source.onended = () => {
      this._activeSources.delete(source);
      try { source.disconnect(); } catch (_) {}
    };
    this._activeSources.add(source);

    const currentTime = this.audioContext.currentTime;
    if (this.nextStartTime < currentTime) this.nextStartTime = currentTime + 0.05;

    try {
      source.start(this.nextStartTime);
      this.nextStartTime += buffer.duration;
    } catch (_) {
      this.nextStartTime = currentTime + 0.05;
      try {
        source.start(this.nextStartTime);
        this.nextStartTime += buffer.duration;
      } catch (_) {}
    }
  }

  stop() {
    try { if (this._vuRaf) cancelAnimationFrame(this._vuRaf); } catch (_) {}
    this._vuRaf = null;

    try { if (this._tickTimer) clearInterval(this._tickTimer); } catch (_) {}
    this._tickTimer = null;

    this._removeAutoResume();

    try { if (this.stream) this.stream.getTracks().forEach((t) => t.stop()); } catch (_) {}

    try {
      if (this.workletNode) this.workletNode.disconnect();
      if (this.silentGain) this.silentGain.disconnect();
      if (this.analyser) this.analyser.disconnect();
      if (this.sourceNode) this.sourceNode.disconnect();
    } catch (_) {}

    try { if (this.audioContext) this.audioContext.close(); } catch (_) {}

    this.audioContext = null;
    this.stream = null;
    this.sourceNode = null;

    this.workletNode = null;
    this.silentGain = null;
    this._workletOk = false;

    this.analyser = null;
    this.analyserData = null;

    this.nextStartTime = 0;
    this._playbackActiveUntil = 0;
    this._activeSources.clear();

    this._isSpeaking = false;
    this._speechStartAt = 0;
    this._lastVoiceAt = 0;

    this._energy = 0;
  }
}

window.MediaHandler = MediaHandler;
