/**
 * JARVINA GEMINI CLIENT (Atualizado + Keepalive)
 *
 * Responsabilidades:
 * - Conectar no WebSocket do Railway
 * - Enviar setup inicial {admin_token}
 * - Enviar áudio em chunks (base64) no formato esperado pelo backend:
 *    { realtime_input: { media_chunks: [{data, mime_type}] } }
 * - Enviar fim de fala:
 *    { end_of_turn: true }
 * - Keepalive para manter WS vivo
 */

class GeminiClient {
  constructor(url) {
    this.url = url;
    this.socket = null;

    this.onMessageCallback = null;
    this.onCloseCallback = null;
    this._pendingMessages = [];

    this._keepAliveTimer = null;
    this._lastSendAt = 0;
  }

  connect(adminToken, preferredName = "") {
    return new Promise((resolve, reject) => {
      try {
        if (typeof adminToken !== "string" || !adminToken.trim()) {
          reject(new Error("Admin token ausente na sessao."));
          return;
        }

        this.socket = new WebSocket(this.url);

        this.socket.onopen = () => {
          console.log("[GeminiClient] WS aberto:", this.url);

          // Setup inicial para o backend
          const setup = { admin_token: adminToken };
          if (typeof preferredName === "string" && preferredName.trim()) {
            setup.preferred_name = preferredName.trim();
          }
          this.socket.send(JSON.stringify(setup));
          console.log("[GeminiClient] Setup enviado.");

          // Keepalive a cada 15s
          this._startKeepAlive();

          resolve();
        };

        this.socket.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            if (this.onMessageCallback) {
              this.onMessageCallback(data);
            } else {
              this._pendingMessages.push(data);
              if (this._pendingMessages.length > 25) this._pendingMessages.shift();
            }
          } catch (e) {
            console.error("[GeminiClient] Mensagem inválida do servidor:", e, event.data);
          }
        };

        this.socket.onclose = (ev) => {
          console.log("[GeminiClient] WS fechado:", ev.code, ev.reason);
          this._stopKeepAlive();
          if (this.onCloseCallback) this.onCloseCallback(ev);
        };

        this.socket.onerror = (err) => {
          console.error("[GeminiClient] WS erro:", err);
          // não fecha aqui; onclose geralmente virá em seguida
          reject(err);
        };
      } catch (e) {
        reject(e);
      }
    });
  }

  _startKeepAlive() {
    this._stopKeepAlive();
    this._keepAliveTimer = setInterval(() => {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;

      // ping simples (backend ignora se não usar)
      // mantém o canal ativo em proxies/idle timeout
      const payload = { type: "ping", t: Date.now() };
      try {
        this.socket.send(JSON.stringify(payload));
      } catch (_) {}
    }, 15000);
  }

  _stopKeepAlive() {
    if (this._keepAliveTimer) {
      clearInterval(this._keepAliveTimer);
      this._keepAliveTimer = null;
    }
  }

  /**
   * Envia um chunk "realtime" em base64.
   * chunk = { data:"<base64>", mime_type:"audio/pcm;rate=16000" }
   */
  sendRealtimeChunk(chunk, endOfTurn = false) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;

    const message = {
      realtime_input: {
        media_chunks: [chunk],
      },
      end_of_turn: !!endOfTurn,
    };

    try {
      this.socket.send(JSON.stringify(message));
      this._lastSendAt = Date.now();
      // Debug opcional (comente se poluir):
      // console.log("[GeminiClient] audio chunk enviado:", chunk.mime_type, chunk.data?.length || 0);
    } catch (e) {
      console.error("[GeminiClient] Falha ao enviar chunk:", e);
    }
  }

  /**
   * Envia sinal de fim de fala (sem áudio).
   * O backend traduz isso para audio_stream_end=True
   */
  sendEndOfTurn() {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;

    try {
      this.socket.send(JSON.stringify({ end_of_turn: true }));
      // console.log("[GeminiClient] end_of_turn enviado");
    } catch (e) {
      console.error("[GeminiClient] Falha ao enviar end_of_turn:", e);
    }
  }

  sendMemorySet(preferredName) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    if (typeof preferredName !== "string") return;
    const value = preferredName.trim();
    if (!value) return;

    try {
      this.socket.send(JSON.stringify({ type: "memory_set", preferred_name: value }));
    } catch (e) {
      console.error("[GeminiClient] Falha ao enviar memory_set:", e);
    }
  }

  disconnect() {
    try {
      this._stopKeepAlive();

      if (this.socket && this.socket.readyState === WebSocket.OPEN) {
        try {
          this.socket.send(JSON.stringify({ type: "close" }));
        } catch (_) {}
      }

      if (this.socket) {
        this.socket.close();
      }
    } catch (_) {
    } finally {
      this.socket = null;
    }
  }

  drainPendingMessages() {
    if (!this.onMessageCallback) return;
    while (this._pendingMessages.length > 0) {
      const next = this._pendingMessages.shift();
      try {
        this.onMessageCallback(next);
      } catch (e) {
        console.error("[GeminiClient] Falha ao processar mensagem pendente:", e);
      }
    }
  }
}

window.GeminiClient = GeminiClient;
