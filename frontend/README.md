# Frontend

The portfolio and the chat page of the AI Digital Twin, served at
[msalmansaeedch.de](https://msalmansaeedch.de). Next.js App Router, JavaScript,
hosted on AWS Amplify. Every page lives under `/en` or `/de`.

The project overview, architecture and deployment are in the
[root README](../README.md); the non-obvious rules (locale routing, metadata,
the chat page's mobile layout, the job-fit check) are in
[CLAUDE.md](../CLAUDE.md). This Next.js version differs from older ones — see
[AGENTS.md](AGENTS.md) before changing framework code.

## Develop

```bash
npm install
npm run dev        # http://localhost:3000
```

The chat page calls the API at `NEXT_PUBLIC_API_URL` (default
`http://localhost:8000`). To use the deployed backend:

```bash
echo "NEXT_PUBLIC_API_URL=$(cd ../terraform && terraform output -raw api_gateway_url)" > .env.local
```

## Test

The browser suites run against a production build:

```bash
npm run build && npx next start -p 3100 &
npm run test:i18n        # locales, metadata, language hint, toggle scroll
npm run test:chat        # chat input, history limits, answer trace, job fit + PDF
npm run test:i18n:sweep  # strings identical in /en and /de (report, not a gate)
```

First run needs the browser: `npx playwright install chromium`.
