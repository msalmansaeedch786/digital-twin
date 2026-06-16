# 🤖 AI Digital Twin — Open Source RAG Architecture

Welcome to the **AI Digital Twin** project! This repository contains a production-ready Retrieval-Augmented Generation (RAG) system that powers a conversational AI avatar. 

This project demonstrates how to build, secure, and deploy a decoupled architecture using **Next.js (Frontend)** and **FastAPI + Langchain (Backend)**, running entirely on free-tier cloud providers (Vercel & Render) with zero hallucination guarantees.

---

## 🌟 Key Features

- **Strict Anti-Hallucination Guardrails**: The LLM is strictly constrained by a prompt system that forces it to refuse questions outside its factual database.
- **GitOps Data Pipeline**: Vector database (ChromaDB) generation is fully automated during the CI/CD build phase.
- **Enterprise-Grade Security**: Includes rate limiting, CORS whitelisting, prompt injection defenses, and strict payload validation.
- **"2 LLMs, 1 Embedding" Workflow**: Uses conversational history to rewrite queries before factual retrieval.

---

## 🏛️ System Architecture

The system is decoupled into two independent services:

1. **Frontend (Vercel)**: A static Next.js React application that provides the glassmorphism UI and Markdown-rendered chat interface.
2. **Backend API (Render)**: A Python FastAPI application that orchestrates the Langchain RAG pipeline.

```mermaid
graph TD
    subgraph "Frontend (Vercel)"
        UI[Next.js React UI]
        MD[React Markdown Renderer]
    end

    subgraph "Backend (Render)"
        API[FastAPI Server]
        RAG[Langchain RAG Engine]
        DB[(ChromaDB Vector Store)]
        SEC[Security Layer: slowapi, CORS]
    end

    subgraph "External AI Services"
        GROQ[Groq Cloud: Llama 3]
        EMB[FastEmbed: BAAI/bge-small]
    end

    User((User)) -->|HTTPS POST| UI
    UI -->|JSON Request| SEC
    SEC --> API
    API --> RAG
    RAG <--> DB
    RAG <--> GROQ
    RAG <--> EMB
```

---

## 🔄 The CI/CD Data Pipeline (The "Brain" Build)

To avoid bloating the Git repository with massive binary vector databases, the data ingestion process is fully automated during the **Render Build Phase**. 

**How it works:**
1. Maintainers update simple `.txt` files in the `data/` directory.
2. Code is pushed to GitHub.
3. Render catches the webhook and runs the build command (`pip install && python ingest.py`).
4. The Python script slices the text files, generates mathematical vectors using FastEmbed, and builds a fresh ChromaDB snapshot on the server.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as GitHub
    participant Render as Render Build Server
    participant Chroma as Local ChromaDB

    Dev->>Git: git push (Update data/*.txt files)
    Git->>Render: Webhook Trigger
    Note over Render: Build Phase Starts
    Render->>Render: pip install dependencies
    Render->>Render: python ingest.py
    Render->>Chroma: Chunk & Embed Text Data
    Note over Render: Build Successful
    Render->>Render: Bake ChromaDB into Image
    Note over Render: Start Phase Starts
    Render->>Render: uvicorn main:app
```

---

## 💬 The Request Lifecycle (Step-by-Step RAG)

When a user asks a question, the system must translate natural language into a mathematical search, retrieve facts, and generate a conversational response.

**The "2 LLMs, 1 Embedding" Workflow:**

```mermaid
sequenceDiagram
    participant User
    participant Vercel as Frontend (Next.js)
    participant FastAPI as Backend (Render)
    participant Llama1 as Groq LLM (Query Rewrite)
    participant Embed as FastEmbed
    participant DB as ChromaDB
    participant Llama2 as Groq LLM (Generator)

    User->>Vercel: "How long were you there?"
    Vercel->>FastAPI: POST /chat + History
    
    Note over FastAPI: Security Checks (CORS, Rate Limit)
    
    FastAPI->>Llama1: History + "How long were you there?"
    Llama1-->>FastAPI: "How long did Salman work at MBition?"
    
    FastAPI->>Embed: Embed Rewritten Question
    Embed-->>FastAPI: [0.012, -0.045, 0.88...] (Math Vector)
    
    FastAPI->>DB: Search for closest vectors
    DB-->>FastAPI: Top 5 Text Chunks (Facts)
    
    FastAPI->>Llama2: System Prompt + Facts + Question
    
    Note over Llama2: "Generate answer using ONLY provided facts"
    
    Llama2-->>FastAPI: Stream response tokens
    FastAPI-->>Vercel: Stream response chunks
    Vercel-->>User: Rendered Markdown UI
```

---

## 🛡️ Security Measures

This API is hardened against both traditional web vulnerabilities and AI-specific attack vectors:

- **CORS Restriction**: `ALLOWED_ORIGINS` strictly limits API access to the Vercel frontend.
- **Rate Limiting**: `slowapi` restricts users to 15 requests per minute per IP address.
- **Input Validation**: Pydantic models cap message lengths (1000 chars) and chat history size.
- **Prompt Injection Defense**: Explicit system directives prevent the LLM from revealing its instructions or assuming different personas.
- **Strict Ignorance Guardrail**: The LLM is instructed to explicitly say "I don't know" rather than hallucinate technologies or tools not found in the vector database.

---

## 🚀 Getting Started Locally

### 1. Backend Setup
```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Create .env based on .env.example
cp .env.example .env
# Edit .env and add your GROQ_API_KEY

# Ingest your personal data
python ingest.py

# Start the server
uvicorn main:app --reload
```

### 2. Frontend Setup
```bash
cd frontend
npm install
npm run dev
```

Visit `http://localhost:3000` to interact with your local Digital Twin.
