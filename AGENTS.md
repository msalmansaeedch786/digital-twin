# Read CLAUDE.md

The guidance for this repository lives in **[CLAUDE.md](CLAUDE.md)**. Read it before
changing anything.

This file exists so agents that look for `AGENTS.md` rather than `CLAUDE.md` —
Cursor's built-in assistant among them — still find it. It is a pointer and not a
copy on purpose: the content is long, specific and changes as the system does, and
a second copy would be wrong within a week. The repository already spent real
effort removing duplication of exactly this shape.

What is in there that you will otherwise get wrong:

- Putting the Lambdas back in a VPC breaks chat, and does it by hanging rather
  than erroring.
- `AI_PROVIDER=ollama` against the cloud vector index corrupts retrieval silently,
  because both embedding models produce 1024 dimensions.
- `experiences`, `projects` and `education` are keyed by slug across three files.
- The knowledge base is English-only by design; do not "fix" German by translating
  `data/`.

`frontend/` has its own [AGENTS.md](frontend/AGENTS.md), written and re-added by
`next dev`, warning that this Next.js differs from training-data Next.js. Read that
one too before touching the frontend.
