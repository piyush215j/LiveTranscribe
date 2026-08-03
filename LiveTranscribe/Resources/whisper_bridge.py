#!/usr/bin/env python3
"""
whisper_bridge.py — LiveTranscribe
===================================
Reads 16 kHz mono Int16 PCM audio from stdin in chunks,
runs faster-whisper inference, and writes JSON segment lines to stdout.

Protocol
--------
stdin  : raw 16-bit signed little-endian PCM @ 16000 Hz, mono
stdout : newline-delimited JSON lines

Startup messages (status):
  {"status": "loading", "model": "<name>"}
  {"status": "ready",   "model": "<name>"}

Segment output:
  {"type": "segment", "text": "...", "start": 0.0, "end": 2.4, "language": "en", "probability": 0.99}

Error output:
  {"type": "error", "message": "..."}

Usage
-----
  python3 whisper_bridge.py --model base [--language en]

Dependencies
------------
  pip3 install faster-whisper
"""

import sys
import json
import struct
import argparse
import threading
import numpy as np

# ── Constants ──────────────────────────────────────────────────────────────
SAMPLE_RATE      = 16_000          # Hz — must match Swift capture config
BYTES_PER_SAMPLE = 2               # Int16
STDIN_CHUNK      = 4096            # bytes per stdin.read() call


def log(obj: dict) -> None:
    """Write a JSON line to stdout and flush immediately."""
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def log_error(message: str) -> None:
    log({"type": "error", "message": message})


# ── Argument parsing ────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description="LiveTranscribe Whisper bridge")
    p.add_argument("--model",        default="base",
                   choices=["tiny", "base", "small", "medium", "large-v3"],
                   help="faster-whisper model size")
    p.add_argument("--language",     default=None,
                   help="BCP-47 language code, or omit for auto-detect")
    p.add_argument("--device",       default="cpu",
                   choices=["cpu", "cuda", "auto"],
                   help="Inference device")
    p.add_argument("--compute-type", default="int8",
                   dest="compute_type",
                   choices=["int8", "int8_float16", "float16", "float32"],
                   help="Model quantisation")
    p.add_argument("--chunk",        default=5.0, type=float,
                   help="Audio chunk length in seconds")
    p.add_argument("--overlap",      default=0.5, type=float,
                   help="Overlap between consecutive chunks in seconds")
    p.add_argument("--vad",          default=True,
                   action=argparse.BooleanOptionalAction,
                   help="Enable Voice Activity Detection filter")
    return p.parse_args()


# ── Model loading ───────────────────────────────────────────────────────────

def load_model(args):
    """Import and instantiate the WhisperModel. Exits on failure."""
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        log_error(
            "faster-whisper is not installed.\n"
            "Run:  pip3 install faster-whisper"
        )
        sys.exit(1)

    log({"status": "loading", "model": args.model})

    try:
        model = WhisperModel(
            args.model,
            device=args.device,
            compute_type=args.compute_type,
        )
        log({"status": "ready", "model": args.model})
        return model
    except Exception as exc:
        try:
            model = WhisperModel(args.model, device="cpu", compute_type="float32")
            log({"status": "ready", "model": args.model})
            return model
        except Exception as exc2:
            log_error(f"Failed to load model '{args.model}': {exc2}")
            sys.exit(1)


# ── Audio processing ────────────────────────────────────────────────────────

def pcm_to_float(raw_bytes: bytes) -> np.ndarray:
    """Convert raw Int16 PCM bytes to normalised float32 array."""
    if not raw_bytes:
        return np.array([], dtype=np.float32)
    usable_bytes = len(raw_bytes) - (len(raw_bytes) % BYTES_PER_SAMPLE)
    if usable_bytes == 0:
        return np.array([], dtype=np.float32)
    int16_samples = np.frombuffer(raw_bytes[:usable_bytes], dtype=np.int16)
    return int16_samples.astype(np.float32) / 32768.0


def transcribe_chunk(
    model,
    audio: np.ndarray,
    chunk_start_sample: int,
    language,
    vad: bool,
) -> None:
    """Run inference on one float32 audio chunk and emit JSON lines."""
    if audio.size == 0:
        return

    lang = language if language else None
    try:
        vad_params = dict(threshold=0.35, min_speech_duration_ms=250, min_silence_duration_ms=500) if vad else {}
        segments, info = model.transcribe(
            audio,
            language=lang,
            vad_filter=vad,
            vad_parameters=vad_params if vad else None,
            word_timestamps=False,
            condition_on_previous_text=False,
            beam_size=5,
        )

        for seg in segments:
            text = seg.text.strip()
            if not text:
                continue

            # Calculate absolute wall-clock offsets from session start
            offset_s = chunk_start_sample / SAMPLE_RATE
            log({
                "type":        "segment",
                "text":        text,
                "start":       round(offset_s + seg.start, 2),
                "end":         round(offset_s + seg.end,   2),
                "language":    info.language,
                "probability": round(float(info.language_probability), 3),
            })

    except Exception as exc:
        log_error(f"Transcription error: {exc}")


# ── Main loop ───────────────────────────────────────────────────────────────

def run(model, args):
    chunk_samples   = int(args.chunk   * SAMPLE_RATE)
    overlap_samples = int(args.overlap * SAMPLE_RATE)
    chunk_bytes     = chunk_samples   * BYTES_PER_SAMPLE

    audio_buffer       = bytearray()
    total_samples_read = 0          # cumulative samples consumed (before overlap)

    stdin_bin = sys.stdin.buffer

    while True:
        try:
            raw = stdin_bin.read(STDIN_CHUNK)
        except Exception:
            break

        if not raw:
            # EOF — flush the remainder if at least 0.5 s
            min_flush = int(0.5 * SAMPLE_RATE) * BYTES_PER_SAMPLE
            if len(audio_buffer) >= min_flush:
                audio = pcm_to_float(bytes(audio_buffer))
                transcribe_chunk(
                    model, audio,
                    total_samples_read - len(audio_buffer) // BYTES_PER_SAMPLE,
                    args.language, args.vad
                )
            break

        audio_buffer.extend(raw)

        # When we have a full chunk, transcribe and slide the window
        while len(audio_buffer) >= chunk_bytes:
            chunk_pcm  = bytes(audio_buffer[:chunk_bytes])
            chunk_start = total_samples_read

            audio = pcm_to_float(chunk_pcm)
            transcribe_chunk(
                model, audio, chunk_start, args.language, args.vad)

            # Advance by (chunk - overlap) samples
            advance_samples = chunk_samples - overlap_samples
            advance_bytes   = advance_samples * BYTES_PER_SAMPLE
            audio_buffer    = audio_buffer[advance_bytes:]
            total_samples_read += advance_samples


# ── Entry point ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Ensure stdout is unbuffered for line-by-line JSON output
    sys.stdout.reconfigure(line_buffering=True)

    args  = parse_args()
    model = load_model(args)

    try:
        run(model, args)
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        log_error(f"Bridge crashed: {exc}")
        sys.exit(1)
