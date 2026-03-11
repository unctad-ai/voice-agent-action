/**
 * AudioWorklet processor for TEN VAD mic capture.
 *
 * Buffers incoming audio (at the AudioContext's sample rate — should be 16 kHz)
 * into chunks of `hopSize` samples, then posts each chunk as a Float32Array
 * to the main thread for VAD inference.
 */
class TenVADProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.hopSize = options?.processorOptions?.hopSize ?? 256;
    this.buffer = new Float32Array(this.hopSize);
    this.offset = 0;
    this.active = true;

    this.port.onmessage = (e) => {
      if (e.data?.type === 'stop') {
        this.active = false;
      }
    };
  }

  process(inputs) {
    if (!this.active) return false;

    const input = inputs[0]?.[0];
    if (!input) return true;

    let srcOffset = 0;
    while (srcOffset < input.length) {
      const remaining = this.hopSize - this.offset;
      const toCopy = Math.min(remaining, input.length - srcOffset);

      this.buffer.set(input.subarray(srcOffset, srcOffset + toCopy), this.offset);
      this.offset += toCopy;
      srcOffset += toCopy;

      if (this.offset >= this.hopSize) {
        // Send a copy to main thread
        this.port.postMessage(
          { type: 'audio', samples: this.buffer.slice() },
          // No transfer — slice() already copied
        );
        this.offset = 0;
      }
    }

    return true;
  }
}

registerProcessor('ten-vad-processor', TenVADProcessor);
