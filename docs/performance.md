# Performance

Whisper records stage timings for successful dictations in:

`~/Library/Application Support/Whisper/latency.json`

Each sample contains provider, batch or streaming transport, word count, STT, cleanup, paste, and release-to-paste latency. The app logs rolling p50 and p95 over the latest 100 samples.

Groq performs an authenticated model-list request during startup. This warms DNS, TLS, and the shared HTTP/2 session without consuming inference quota.

Deepgram uses live WebSocket transcription when selected as the STT provider. Audio is sent while the user speaks. If streaming fails or produces no transcript, the existing bounded batch/fallback path runs.

Run the local provider benchmark:

```bash
python3 scripts/benchmark-stt.py --runs 2
```

It generates short, long, and noisy fixtures, compares configured Groq, Deepgram, and ElevenLabs accounts, reports median/p95 latency and word error rate, then saves detailed local results under Whisper Application Support. Benchmark calls consume provider quota.

July 14, 2026 local two-run benchmark across all three fixtures:

| Provider | Median | p95 | Mean WER |
|---|---:|---:|---:|
| Deepgram batch | 647 ms | 955 ms | 5.6% |
| Groq batch | 711 ms | 1,122 ms | 11.1% |
| ElevenLabs batch | 1,078 ms | 2,298 ms | 5.6% |

Deepgram is the default for new installs because it won both latency and accuracy here, and its streaming path moves most work before key release. Existing saved provider choices remain unchanged.
