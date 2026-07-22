#!/usr/bin/env python3
import concurrent.futures
import json
import os
import pathlib
import re
import subprocess
import time
import urllib.parse
import urllib.request
import urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[1]
RESULTS = pathlib.Path.home() / "Library/Application Support/Whisper/benchmarks/tech-terms-latest.json"
FIXTURES = pathlib.Path.home() / "Library/Application Support/Whisper/benchmarks/tech-term-fixtures"
SPOKEN = {
    ".gitignore": "dot git ignore", "gitignore": "git ignore", "gitignored": "git ignored",
    "AGENTS.md": "agents dot M D", "CLAUDE.md": "Claude dot M D", ".env": "dot E N V",
    "README.md": "read me dot M D", "package.json": "package dot JSON",
    "tsconfig.json": "T S config dot JSON", "GPT-5": "GPT five", "C++": "C plus plus",
    "C#": "C sharp", "Objective-C": "Objective C", "Next.js": "Next dot J S",
    "Node.js": "Node dot J S", "whisper.cpp": "Whisper dot C P P", "llama.cpp": "Llama dot C P P",
}


def keyterms():
    source = (ROOT / "Sources/Whisper/Store/Settings.swift").read_text()
    block = source[source.index("let defaultVocabulary"):source.index("/// SuperWhisper-style")]
    entries = re.findall(r'VocabularyEntry\(from: "([^"]+)"(?:, to: "([^"]+)")?\)', block)
    result, seen = [], set()
    for source_term, target in entries:
        term = target or source_term
        if term.casefold() not in seen:
            seen.add(term.casefold())
            result.append(term)
    return result[:100]


def key(name):
    value = os.environ.get(name)
    if value:
        return value
    secrets = pathlib.Path.home() / "Library/Application Support/Whisper/secrets.json"
    aliases = {"DEEPGRAM_API_KEY": "deepgram", "GROQ_API_KEY": "groq"}
    return json.loads(secrets.read_text()).get(aliases[name], "")


def normalize(value):
    return " ".join(re.findall(r"[a-z0-9]+", value.casefold()))


def recognized(term, text):
    actual = normalize(text)
    accepted = {normalize(term), normalize(SPOKEN.get(term, term))}
    return any(value and value in actual for value in accepted)


def request_json(url, headers, body):
    for attempt in range(8):
        request = urllib.request.Request(url, data=body, method="POST", headers=headers | {"User-Agent": "Whisper/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 7:
                raise
            time.sleep(float(error.headers.get("Retry-After", 2 ** attempt)))


def transcribe(wav, terms, api_key):
    query = urllib.parse.urlencode(
        [("model", "nova-3"), ("smart_format", "true")] + [("keyterm", term) for term in terms]
    )
    data = request_json(
        f"https://api.deepgram.com/v1/listen?{query}",
        {"Authorization": f"Token {api_key}", "Content-Type": "audio/wav"},
        wav,
    )
    return data["results"]["channels"][0]["alternatives"][0]["transcript"]


def cleanup(text, terms, api_key):
    instruction = (
        "Clean raw software-engineering dictation. Output only cleaned text. Preserve meaning and wording. "
        "Fix obvious phonetic technical-term errors using context. Known spellings: " + ", ".join(terms) + ". "
        'In software context, "clot code" or "quad code" means "Claude Code"; "codec session" means '
        '"Codex session"; "get ignored" may mean "gitignored"; repository files include ".gitignore", '
        '"AGENTS.md", "CLAUDE.md", and ".env".'
    )
    payload = json.dumps({
        "model": "openai/gpt-oss-120b",
        "messages": [{"role": "system", "content": instruction}, {"role": "user", "content": text}],
        "temperature": 0.2, "stream": False, "reasoning_effort": "low", "max_completion_tokens": 2048,
    }).encode()
    data = request_json(
        "https://api.groq.com/openai/v1/chat/completions",
        {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        payload,
    )
    return data["choices"][0]["message"]["content"].strip() or text


def make_wav(term, directory):
    stem = re.sub(r"[^a-z0-9]+", "-", term.casefold()).strip("-")
    aiff, wav = directory / f"{stem}.aiff", directory / f"{stem}.wav"
    if wav.exists():
        return wav.read_bytes()
    subprocess.run(["say", "-v", "Samantha", "-r", "165", "-o", aiff, f"The software term is {SPOKEN.get(term, term)}."], check=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", aiff, "-ar", "16000", "-ac", "1", wav], check=True)
    return wav.read_bytes()


def main():
    for env_name in list(os.environ):
        if "proxy" in env_name.lower():
            del os.environ[env_name]
    terms = keyterms()
    assert len(terms) == 100, f"Expected 100 Deepgram keyterms, got {len(terms)}"
    deepgram, groq = key("DEEPGRAM_API_KEY"), key("GROQ_API_KEY")
    if not deepgram or not groq:
        raise SystemExit("DEEPGRAM_API_KEY and GROQ_API_KEY required")
    started = time.time()
    FIXTURES.mkdir(parents=True, exist_ok=True)
    audio = {term: make_wav(term, FIXTURES) for term in terms}
    try:
        def run(term):
            raw = transcribe(audio[term], terms, deepgram)
            final = cleanup(raw, terms, groq)
            return {"term": term, "raw": raw, "final": final,
                    "rawPass": recognized(term, raw), "finalPass": recognized(term, final)}
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            rows = list(pool.map(run, terms))
    finally:
        for aiff in FIXTURES.glob("*.aiff"):
            aiff.unlink()
    result = {
        "date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "cases": len(rows), "rawScore": sum(x["rawPass"] for x in rows),
        "finalScore": sum(x["finalPass"] for x in rows), "seconds": round(time.time() - started, 2),
        "failures": [x for x in rows if not x["finalPass"]], "results": rows,
    }
    RESULTS.parent.mkdir(parents=True, exist_ok=True)
    RESULTS.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Deepgram raw: {result['rawScore']}/100")
    print(f"End-to-end: {result['finalScore']}/100")
    for row in result["failures"]:
        print(f"MISS {row['term']}: {row['raw']} -> {row['final']}")
    print(f"Saved {RESULTS}")
    raise SystemExit(0 if result["finalScore"] >= 95 else 1)

if __name__ == "__main__":
    main()
