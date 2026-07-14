#!/usr/bin/env python3
import argparse
import json
import math
import pathlib
import statistics
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
import uuid

SECRETS = pathlib.Path.home() / "Library/Application Support/Whisper/secrets.json"
RESULTS = pathlib.Path.home() / "Library/Application Support/Whisper/benchmarks/latest.json"

CASES = {
    "short": "Whisper should paste this sentence quickly.",
    "long": (
        "Please update the project notes with today's latency measurements, compare the speech providers, "
        "keep the fastest reliable option, and make sure the final transcript preserves names, numbers, "
        "punctuation, and technical terms without changing my tone or adding extra commentary."
    ),
    "noisy": "Whisper should still understand this sentence with background noise.",
}


def multipart(fields, file_field, filename, content_type, payload):
    boundary = "----WhisperBenchmark" + uuid.uuid4().hex
    chunks = []
    for key, value in fields.items():
        chunks += [
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n".encode()
        ]
    chunks += [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"{filename}\"\r\nContent-Type: {content_type}\r\n\r\n".encode(),
        payload,
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    return boundary, b"".join(chunks)


def request_json(url, headers, body, content_type):
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={**headers, "Content-Type": content_type, "User-Agent": "Whisper/0.1"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def transcribe(provider, key, wav):
    if provider == "groq":
        boundary, body = multipart(
            {"model": "whisper-large-v3-turbo", "response_format": "json"},
            "file", "audio.wav", "audio/wav", wav,
        )
        data = request_json(
            "https://api.groq.com/openai/v1/audio/transcriptions",
            {"Authorization": f"Bearer {key}"}, body, f"multipart/form-data; boundary={boundary}",
        )
    elif provider == "deepgram":
        query = urllib.parse.urlencode({"model": "nova-3", "smart_format": "true"})
        data = request_json(
            f"https://api.deepgram.com/v1/listen?{query}",
            {"Authorization": f"Token {key}"}, wav, "audio/wav",
        )
        return data["results"]["channels"][0]["alternatives"][0]["transcript"]
    elif provider == "elevenlabs":
        boundary, body = multipart(
            {"model_id": "scribe_v2"}, "file", "audio.wav", "audio/wav", wav,
        )
        data = request_json(
            "https://api.elevenlabs.io/v1/speech-to-text",
            {"xi-api-key": key}, body, f"multipart/form-data; boundary={boundary}",
        )
    else:
        raise ValueError(provider)
    return data["text"]


def words(text):
    return "".join(c.lower() if c.isalnum() or c.isspace() else " " for c in text).split()


def wer(reference, hypothesis):
    a, b = words(reference), words(hypothesis)
    row = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        new = [i]
        for j, right in enumerate(b, 1):
            new.append(min(new[-1] + 1, row[j] + 1, row[j - 1] + (left != right)))
        row = new
    return row[-1] / max(1, len(a))


def make_audio(directory):
    output = {}
    for name, text in CASES.items():
        aiff = directory / f"{name}.aiff"
        clean = directory / f"{name}-clean.wav"
        wav = directory / f"{name}.wav"
        subprocess.run(["say", "-o", aiff, text], check=True)
        subprocess.run(["afconvert", aiff, clean, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"], check=True)
        if name == "noisy" and pathlib.Path("/opt/homebrew/bin/ffmpeg").exists():
            subprocess.run([
                "/opt/homebrew/bin/ffmpeg", "-loglevel", "error", "-y", "-i", clean,
                "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.025:sample_rate=16000",
                "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first:weights='1 0.35'",
                "-ar", "16000", "-ac", "1", wav,
            ], check=True)
        else:
            wav.write_bytes(clean.read_bytes())
        output[name] = wav
    return output


def main():
    parser = argparse.ArgumentParser(description="Benchmark Whisper STT providers on short, long, and noisy clips.")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--providers", nargs="*", choices=("groq", "deepgram", "elevenlabs"))
    args = parser.parse_args()
    secrets = json.loads(SECRETS.read_text())
    requested = args.providers or ("groq", "deepgram", "elevenlabs")
    providers = [name for name in requested if secrets.get(name)]
    if not providers:
        raise SystemExit("No Groq, Deepgram, or ElevenLabs keys configured")

    rows = []
    with tempfile.TemporaryDirectory(prefix="whisper-benchmark-") as raw_dir:
        clips = make_audio(pathlib.Path(raw_dir))
        for run in range(args.runs):
            for case, path in clips.items():
                wav = path.read_bytes()
                for provider in providers:
                    started = time.perf_counter()
                    try:
                        transcript = transcribe(provider, secrets[provider], wav)
                        rows.append({
                            "provider": provider, "case": case, "run": run + 1,
                            "latency_ms": round((time.perf_counter() - started) * 1000, 1),
                            "wer": round(wer(CASES[case], transcript), 4), "transcript": transcript,
                        })
                    except Exception as error:
                        rows.append({"provider": provider, "case": case, "run": run + 1, "error": str(error)})

    summary = []
    for provider in providers:
        valid = [row for row in rows if row["provider"] == provider and "latency_ms" in row]
        summary.append({
            "provider": provider,
            "median_ms": round(statistics.median(row["latency_ms"] for row in valid), 1) if valid else None,
            "p95_ms": round(sorted(row["latency_ms"] for row in valid)[math.ceil(len(valid) * .95) - 1], 1) if valid else None,
            "mean_wer": round(statistics.mean(row["wer"] for row in valid), 4) if valid else None,
            "successes": len(valid),
        })
    report = {"created_at": time.time(), "runs": args.runs, "summary": summary, "samples": rows}
    RESULTS.parent.mkdir(parents=True, exist_ok=True)
    RESULTS.write_text(json.dumps(report, indent=2))
    print("provider       median    p95       mean WER  success")
    for row in summary:
        print(f"{row['provider']:<14} {str(row['median_ms']):>7}ms {str(row['p95_ms']):>7}ms {str(row['mean_wer']):>9} {row['successes']:>7}")
    print(f"\nSaved {RESULTS}")


if __name__ == "__main__":
    main()
