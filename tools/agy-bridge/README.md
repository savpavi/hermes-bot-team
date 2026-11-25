# agy-bridge

`pc-agy` lets the server use a Google AI Pro subscription through Google's own client, the
Antigravity CLI (`agy`), which runs on my desktop.

Hermes can't use the subscription as a model provider. Its Gemini provider takes an API key,
which is billed separately. Tools that copy the CLI's OAuth login into other apps break
Google's terms, and accounts were suspended for it in early 2026. So the bots don't call
Gemini directly. They run the official binary over SSH and read its plain-text answer.

```bash
pc-agy --models
pc-agy "Summarize this box score in two sentences: ..." "Gemini 4 Neon (Medium)"
```

Rules I keep:

- **Public data only.** The desktop CLI is a worker, not a trusted agent: no personal mail,
  finance or notes-vault content goes through it.
- **The desktop has to be on.** I only use it for jobs that already depend on the desktop
  being awake (my fantasy data pull runs there every morning).
- **Measure before switching.** For a template-style daily digest, Gemini and the small cron
  model gave roughly the same quality. One gave category ranks, the other kept every
  suggested pair. Bigger models only pay off where the job needs reasoning.
