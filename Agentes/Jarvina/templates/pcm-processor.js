/**
 * pcm-processor.js (AudioWorklet)
 *
 * - Recebe áudio do microfone (Float32)
 * - Converte para PCM 16-bit (Int16) em chunks de ~20ms (dinâmico por sample rate)
 * - Calcula energia (RMS) do chunk para VU meter
 * - Envia para o main thread:
 *    { pcm: ArrayBuffer, energy: number, sampleRate: number }
 */

class PCMProcessor extends AudioWorkletProcessor {
  constructor() {
    super();

    // 20ms com a taxa real do AudioContext (ex.: 16k=320, 48k=960)
    this.sampleRateHz = sampleRate;
    this.TARGET_CHUNK_SAMPLES = Math.max(160, Math.round(this.sampleRateHz * 0.02));

    // buffer interno
    this._floatBuf = new Float32Array(this.TARGET_CHUNK_SAMPLES);
    this._writeIndex = 0;
  }

  _flushChunk() {
    // Converte Float32 -> Int16 (PCM)
    const int16 = new Int16Array(this.TARGET_CHUNK_SAMPLES);

    // RMS (energia)
    let sumSq = 0;

    for (let i = 0; i < this.TARGET_CHUNK_SAMPLES; i++) {
      let s = this._floatBuf[i];

      // clamp
      if (s > 1) s = 1;
      if (s < -1) s = -1;

      sumSq += s * s;

      // float -> int16
      // (s * 32767) com saturação
      int16[i] = (s * 32767) | 0;
    }

    const rms = Math.sqrt(sumSq / this.TARGET_CHUNK_SAMPLES); // ~0..0.3
    const energy = rms; // vamos usar RMS diretamente

    // Envia para o main thread
    // Importante: transfere o buffer para reduzir custo
    this.port.postMessage({ pcm: int16.buffer, energy, sampleRate: this.sampleRateHz }, [int16.buffer]);

    // reset
    this._writeIndex = 0;
  }

  process(inputs) {
    const input = inputs && inputs[0] && inputs[0][0];
    if (!input) return true;

    // input é Float32Array com frames (normalmente 128 por callback)
    for (let i = 0; i < input.length; i++) {
      this._floatBuf[this._writeIndex++] = input[i];

      if (this._writeIndex >= this.TARGET_CHUNK_SAMPLES) {
        this._flushChunk();
      }
    }

    return true;
  }
}

registerProcessor("pcm-processor", PCMProcessor);
