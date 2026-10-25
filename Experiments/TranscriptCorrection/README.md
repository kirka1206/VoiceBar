# Local transcript correction experiment

This experiment tests whether an already installed local text model can fix context-dependent errors after Whisper and the deterministic normalizer have produced a complete transcript. It is not part of VoiceBar's production path.

## Data and privacy

- The fixture transcripts are synthetic and contain no audio.
- The runner calls only the local Ollama API at `127.0.0.1`; it does not pull or download a model.
- It checks `/api/tags` first and stops if the requested model is not already installed.
- Model outputs and the JSON report are written outside the repository by default (`/tmp`). No source audio is read or saved.

## Run

From the repository root, with Ollama already running and the model already installed:

```sh
swift run TranscriptCorrectionEvaluation --model gemma4:latest
```

An optional `--output /absolute/path/report.json` selects the report destination. The runner records the installed model digest, fixture outputs, word error rates, labeled term-correction outcomes, inference timings, and sampled Ollama process RSS. RSS is a process-level estimate and may count shared resident pages; it is not a precise measurement of total unified-memory pressure.

The fixture set includes `текстурой` in both a suspected recognition error and a correct ordinary sentence, plus the voice-like variants `VMVM` and `Vesphere`. This checks contextual correction and preservation of already-correct text. The dataset is small and synthetic, so its scores are directional evidence, not a general accuracy estimate.

No numeric U2 thresholds for quality, false changes, latency, or memory were agreed before evaluation. The report therefore records measurements only and makes no production go/no-go recommendation.
