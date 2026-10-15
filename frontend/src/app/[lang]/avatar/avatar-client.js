"use client";

import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Mic, MicOff, Home, Volume2, VolumeX, Briefcase } from "lucide-react";
import Link from "next/link";
import { otherLocale } from "../../dictionaries/locales";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

const NAME_STORAGE_KEY = "chat-user-name";
const MAX_TEXTAREA_PX = 160; // ~6 lines, then the textarea scrolls internally

// Mirror ChatRequest in lambdas/api/main.py. The API rejects a request whose
// history holds more than 20 items or any item longer than 2000 characters
// with a 422, which this page can only report as a lost connection. Sending the
// whole transcript used to trip that on the 11th question, and every question
// after it failed the same way, so a long conversation simply stopped working.
const MAX_HISTORY_MESSAGES = 20;
const MAX_HISTORY_CHARS = 2000;
// ChatRequest.message is capped at 1000 too. Enforced on the textarea so an
// over-long message cannot be typed or pasted, rather than being sent and
// coming back as "lost my connection".
const MAX_MESSAGE_CHARS = 1000;

const TRACE_STEP_COLORS = {
  rewrite: "#a78bfa",
  embed: "#4facfe",
  search: "#22c55e",
  generate: "#00f2fe",
};

/**
 * "How this answer was made": the steps the backend timed, what it searched
 * for, how many knowledge-base facts the answer drew on, and what it cost.
 * Everything here comes from the API's `trace`; nothing is computed in the
 * browser except formatting. The facts themselves are deliberately not shown —
 * only how many were used.
 */
function TracePanel({ trace, lang, dict }) {
  const [open, setOpen] = useState(false);
  const t = dict.avatar;
  const num = new Intl.NumberFormat(lang);
  const seconds = (ms) => `${new Intl.NumberFormat(lang, { maximumFractionDigits: 2 }).format(ms / 1000)} s`;
  const stepLabel = {
    rewrite: t.traceStepRewrite,
    embed: t.traceStepEmbed,
    search: t.traceStepSearch,
    generate: t.traceStepGenerate,
  };
  const stepTotal = trace.steps.reduce((sum, s) => sum + s.ms, 0) || 1;

  return (
    <div className="trace">
      <button type="button" className="trace-toggle" onClick={() => setOpen(o => !o)} aria-expanded={open}>
        {open ? t.traceHide : t.traceToggle}
      </button>
      {open && (
        <div className="trace-panel">
          <div className="trace-section">
            <div className="trace-heading">{t.traceSearched}</div>
            <div className="trace-query">“{trace.search_query}”</div>
          </div>

          <div className="trace-section">
            <div className="trace-heading">{t.traceSteps} · {seconds(trace.total_ms)}</div>
            <div className="trace-bar" aria-hidden="true">
              {trace.steps.map(s => (
                <span key={s.name} style={{ flexGrow: Math.max(s.ms, 1), background: TRACE_STEP_COLORS[s.name] }} />
              ))}
            </div>
            <ul className="trace-steps">
              {trace.steps.map(s => (
                <li key={s.name}>
                  <span className="trace-dot" style={{ background: TRACE_STEP_COLORS[s.name] }} />
                  <span className="trace-step-name">{stepLabel[s.name]}</span>
                  <span className="trace-step-ms">{num.format(Math.round(s.ms))} ms · {Math.round((s.ms / stepTotal) * 100)}%</span>
                </li>
              ))}
            </ul>
          </div>

          <div className="trace-section trace-facts">
            {t.traceSources}: <strong>{trace.facts_used}</strong>
          </div>

          <div className="trace-section trace-cost">
            {trace.cost_usd != null && (
              <span>{t.traceCost} <strong>${trace.cost_usd.toFixed(5)}</strong> · </span>
            )}
            <span>
              {t.traceTokens
                .replace("{in}", num.format(trace.input_tokens))
                .replace("{out}", num.format(trace.output_tokens))}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

// Mirrors FitRequest.job_description in lambdas/api/main.py.
const FIT_MIN_CHARS = 80;
const FIT_MAX_CHARS = 6000;
const FIT_GROUPS = [
  { verdict: "met", mark: "✅", label: "fitMetGroup" },
  { verdict: "partial", mark: "🟡", label: "fitPartialGroup" },
  { verdict: "missing", mark: "❌", label: "fitMissingGroup" },
];

// Strip any trailing slash so we don't build a "//chat" URL when the configured
// base already ends in "/". NEXT_PUBLIC_API_URL is inlined at build time.
function apiBase() {
  return (process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000").replace(/\/+$/, "");
}

function fill(template, values) {
  return Object.entries(values).reduce((s, [k, v]) => s.replaceAll(`{${k}}`, v), template);
}

function fitScoreLine(fit, t) {
  const count = v => fit.items.filter(i => i.verdict === v).length;
  return fill(t.fitScore, {
    met: count("met"), partial: count("partial"), missing: count("missing"), total: fit.items.length,
  });
}

/**
 * The job-fit result. The summary line is computed here from the final
 * verdicts rather than written by the model: the API's code checks can turn a
 * model's "met" into "missing", and a model-written summary could still praise
 * what was rejected. "Missing" items carry no model text by design, so they
 * show a fixed sentence.
 */
function FitGroups({ fit, t }) {
  return FIT_GROUPS.map(g => {
    const items = fit.items.filter(i => i.verdict === g.verdict);
    if (!items.length) return null;
    return (
      <div key={g.verdict} className={`fit-group fit-${g.verdict}`}>
        <div className="fit-group-title">{g.mark} {t[g.label]} ({items.length})</div>
        <ul>
          {items.map((it, i) => (
            <li key={i}>
              <strong>{it.requirement}</strong>
              <span>{it.verdict === "missing" ? t.fitMissingText : it.evidence}</span>
            </li>
          ))}
        </ul>
      </div>
    );
  });
}

function FitCard({ fit, lang, dict, onDownload }) {
  const t = dict.avatar;
  const seconds = `${new Intl.NumberFormat(lang, { maximumFractionDigits: 1 }).format(fit.trace.total_ms / 1000)} s`;
  return (
    <div className="fit-card">
      <div className="fit-card-title">{t.fitResultTitle}</div>
      <div className="fit-score">{fitScoreLine(fit, t)}</div>
      <FitGroups fit={fit} t={t} />
      <div className="fit-card-footer">
        <button type="button" className="fit-download" onClick={() => onDownload(fit)}>{t.fitDownload}</button>
        <span className="fit-meta">
          {fill(t.fitMeta, {
            s: seconds,
            cost: fit.trace.cost_usd != null ? `$${fit.trace.cost_usd.toFixed(4)}` : "–",
          })}
        </span>
      </div>
      <div className="fit-note">{t.fitNote}</div>
    </div>
  );
}

// jsPDF's built-in Helvetica only encodes WinAnsi (Latin-1 plus a few extras
// such as curly quotes and dashes). German umlauts are fine; anything else —
// an emoji, an arrow — would print as garbage, so it is mapped or dropped.
const PDF_EXTRAS = "‘’‚“”„–—…•€™ŠšŽžŒœŸ";
function pdfSafe(text) {
  return String(text)
    .replace(/[→⇒]/g, "->").replace(/[≥]/g, ">=").replace(/[≤]/g, "<=")
    .replace(/[^\u0000-ÿ]/g, ch => (PDF_EXTRAS.includes(ch) ? ch : ""));
}

/**
 * "Download as PDF": builds the file in the browser and saves it straight to
 * Downloads — no print dialog. jsPDF is imported on click, so the ~350 KB
 * library never weighs on the chat page itself. Text stays real text in the
 * PDF (selectable, searchable), not a screenshot.
 */
async function downloadFitPdf(fit, lang, t) {
  const { jsPDF } = await import("jspdf");
  const doc = new jsPDF({ unit: "mm", format: "a4" });
  const M = 18, W = 210 - 2 * M, BOTTOM = 297 - 18;
  let y = M;
  const ensure = (h) => { if (y + h > BOTTOM) { doc.addPage(); y = M; } };
  const write = (text, { size = 10, bold = false, color = [40, 40, 40], gap = 1.5 } = {}) => {
    doc.setFont("helvetica", bold ? "bold" : "normal");
    doc.setFontSize(size);
    doc.setTextColor(...color);
    const lines = doc.splitTextToSize(pdfSafe(text), W);
    const lh = size * 0.42;
    ensure(lines.length * lh);
    doc.text(lines, M, y + lh * 0.8);
    y += lines.length * lh + gap;
  };

  write(t.fitPrintTitle, { size: 18, bold: true, color: [17, 17, 17], gap: 1 });
  write(new Date().toLocaleDateString(lang, { dateStyle: "long" }), { size: 9.5, color: [110, 110, 110], gap: 5 });
  write(fitScoreLine(fit, t), { size: 11, color: [34, 34, 34], gap: 6 });

  const groupColor = { met: [21, 128, 61], partial: [161, 98, 7], missing: [185, 28, 28] };
  for (const g of FIT_GROUPS) {
    const items = fit.items.filter(i => i.verdict === g.verdict);
    if (!items.length) continue;
    ensure(14);
    doc.setFillColor(...groupColor[g.verdict]);
    doc.circle(M + 1.5, y + 2.6, 1.5, "F");
    doc.setFont("helvetica", "bold");
    doc.setFontSize(10);
    doc.setTextColor(...groupColor[g.verdict]);
    doc.text(pdfSafe(`${t[g.label]} (${items.length})`.toUpperCase()), M + 5, y + 3.6);
    y += 8;
    for (const it of items) {
      ensure(12);
      write(it.requirement, { size: 11, bold: true, color: [17, 17, 17], gap: 0.8 });
      write(it.verdict === "missing" ? t.fitMissingText : it.evidence, { size: 10, color: [60, 60, 60], gap: 3.5 });
    }
    y += 2;
  }

  ensure(14);
  doc.setDrawColor(200, 200, 200);
  doc.line(M, y, M + W, y);
  y += 3;
  write(t.fitPrintFooter, { size: 8.5, color: [110, 110, 110] });

  // Local date, not toISOString(): that is UTC, and just after midnight in
  // Germany it named the file after yesterday.
  const now = new Date();
  const date = [now.getFullYear(), now.getMonth() + 1, now.getDate()].map(n => String(n).padStart(2, "0")).join("-");
  doc.save(`Muhammad-Salman-job-fit-${date}.pdf`);
}

/**
 * The conversation as the API should see it: the most recent turns only, each
 * clipped to the API's per-message limit. Messages marked `uiOnly` (the
 * greeting and the error notices) are left out — they are this page talking,
 * not the twin, and feeding "I lost my connection" back as something the twin
 * said would only confuse the next answer.
 */
function historyForApi(messages) {
  return messages
    .filter(m => !m.uiOnly)
    .slice(-MAX_HISTORY_MESSAGES)
    .map(m => ({ role: m.role, content: m.content.slice(0, MAX_HISTORY_CHARS) }));
}

/**
 * Up to two letters for the little chip beside a reader's own messages:
 * "Muhammad Salman" -> MS, "Salman" -> SA. Falls back to the localised "You"
 * label when no name has been given.
 */
function initialsOf(name) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

export default function AvatarClient({ lang, dict }) {
  const [isListening, setIsListening] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [isMuted, setIsMuted] = useState(true); // Default to muted so it doesn't auto-play
  const [inputText, setInputText] = useState("");
  const [messages, setMessages] = useState([
    { role: "bot", content: dict.avatar.greeting, uiOnly: true }
  ]);
  const [voices, setVoices] = useState([]);
  // Empty until the effect below reads localStorage: reading it during render
  // would put a different value in the server HTML than the first client paint.
  const [userName, setUserName] = useState("");

  const recognitionRef = useRef(null);
  const chatScrollRef = useRef(null);
  const rootRef = useRef(null);
  const textareaRef = useRef(null);

  // Job fit: the paste dialog and its text.
  const [fitOpen, setFitOpen] = useState(false);
  const [fitText, setFitText] = useState("");

  // Remember who is typing across visits, so a returning reader is not asked
  // for their name again.
  useEffect(() => {
    try {
      const saved = localStorage.getItem(NAME_STORAGE_KEY);
      if (saved) setUserName(saved);
    } catch {
      // Safari private mode throws on localStorage; the name is a nicety, so
      // carry on without it.
    }
  }, []);

  const handleNameChange = (value) => {
    setUserName(value);
    try {
      if (value.trim()) localStorage.setItem(NAME_STORAGE_KEY, value);
      else localStorage.removeItem(NAME_STORAGE_KEY);
    } catch {}
  };

  // Scroll ONLY the messages container. scrollIntoView() walks every scrollable
  // ancestor including the document itself — on iOS that panned the whole app
  // shell upward (nav pushed off-screen, dead space under the input).
  const scrollToBottom = () => {
    const el = chatScrollRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: "smooth" });
  };

  // The chat UI is always dark. Force it regardless of the portfolio's saved
  // theme, and do NOT write to localStorage so the portfolio keeps the user's choice.
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", "dark");
  }, []);

  // Mobile keyboard fix. 100dvh does NOT shrink when the iOS/Android on-screen
  // keyboard opens, so the bottom of the app (the input bar) ends up behind the
  // keyboard, and dismissing it can leave the input "floating" with dead space.
  // Instead, size the app shell to the *visual viewport* — the region actually
  // visible above the keyboard — and follow it as the keyboard opens/closes.
  useEffect(() => {
    const root = rootRef.current;
    const vv = window.visualViewport;
    if (!root || !vv) return; // CSS 100dvh fallback covers no-visualViewport
    const apply = () => {
      root.style.height = `${vv.height}px`;
      root.style.transform = `translateY(${vv.offsetTop}px)`;
      // Keyboard open? Collapse the tall identity header so the conversation
      // and input get the visible space instead of a giant avatar.
      const keyboardOpen = window.innerHeight - vv.height > 120;
      root.classList.toggle("kb-open", keyboardOpen);
    };
    apply();
    vv.addEventListener("resize", apply);
    vv.addEventListener("scroll", apply);
    return () => {
      vv.removeEventListener("resize", apply);
      vv.removeEventListener("scroll", apply);
    };
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [messages, isSpeaking]);

  useEffect(() => {
    if (typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      const query = params.get("q")?.slice(0, 500)?.replace(/[<>]/g, "");
      if (query) {
        setInputText(query);
      }
    }
  }, []);

  // Initialize Speech Recognition & Voices
  useEffect(() => {
    // 1. Load Voices for TTS
    const loadVoices = () => {
      const availableVoices = window.speechSynthesis.getVoices();
      setVoices(availableVoices);
    };
    loadVoices();
    window.speechSynthesis.onvoiceschanged = loadVoices;

    // 2. Setup Speech Recognition
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (SpeechRecognition) {
      const recognition = new SpeechRecognition();
      recognition.continuous = false;
      recognition.interimResults = true;
      recognition.lang = lang === 'de' ? 'de-DE' : 'en-US';

      recognition.onresult = (event) => {
        let currentTranscript = "";
        for (let i = event.resultIndex; i < event.results.length; i++) {
          currentTranscript += event.results[i][0].transcript;
        }
        setInputText(currentTranscript.slice(0, MAX_MESSAGE_CHARS));
      };

      recognition.onend = () => {
        setIsListening(false);
      };

      recognition.onerror = (event) => {
        console.error("Speech recognition error", event.error);
        setIsListening(false);
      };

      recognitionRef.current = recognition;
    }

    return () => {
      window.speechSynthesis.cancel();
      if (recognitionRef.current) {
        recognitionRef.current.abort();
      }
    };
    // Rebuild the recogniser when the language changes: recognition.lang is set
    // once at construction, so a client-side move between /en/avatar and
    // /de/avatar would otherwise keep listening in the previous language.
  }, [lang]);

  const toggleListening = () => {
    if (!recognitionRef.current) {
      alert(dict.avatar.speechUnsupported);
      return;
    }

    if (isListening) {
      recognitionRef.current.stop();
      setIsListening(false);
    } else {
      window.speechSynthesis.cancel();
      setIsSpeaking(false);
      recognitionRef.current.start();
      setIsListening(true);
    }
  };

  const speak = (text) => {
    if (!window.speechSynthesis) return;

    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);

    // Match the page language, otherwise German text is read aloud by an
    // English voice and is close to unintelligible.
    const wantPrefix = lang === 'de' ? 'de-' : 'en-';
    const preferredVoice =
      voices.find(v => v.lang.startsWith(wantPrefix) &&
        (v.name.includes('Male') || v.name.includes('Google UK English Male') || v.name.includes('Daniel'))) ||
      voices.find(v => v.lang.startsWith(wantPrefix));
    if (preferredVoice) {
      utterance.voice = preferredVoice;
    }

    utterance.lang = lang === 'de' ? 'de-DE' : 'en-US';
    utterance.rate = 1.0;
    utterance.pitch = 0.9;

    utterance.onstart = () => setIsSpeaking(true);
    utterance.onend = () => setIsSpeaking(false);
    utterance.onerror = () => setIsSpeaking(false);

    window.speechSynthesis.speak(utterance);
  };

  const handleSendText = async (text) => {
    if (!text.trim()) return;

    const userMsg = text.trim();
    setInputText("");
    setMessages(prev => [...prev, { role: "user", content: userMsg }]);

    setIsSpeaking(true); // Simulate thinking animation

    try {
      const response = await fetch(`${apiBase()}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // Send previous messages as history so AI remembers the context
        body: JSON.stringify({
          message: userMsg,
          history: historyForApi(messages),
          // Drives the twin's reply language; the API defaults to "en".
          lang,
        }),
      });

      if (!response.ok) {
        // 429 = rate limited: this is a "slow down" hint, not a real outage
        throw new Error(response.status === 429 ? "RATE_LIMIT" : "Network error");
      }

      const data = await response.json();
      // trace is optional: an older API (or a local run) may not send it.
      setMessages(prev => [...prev, { role: "bot", content: data.reply, trace: data.trace }]);
      if (!isMuted) {
        speak(data.reply);
      } else {
        setIsSpeaking(false);
      }
    } catch (error) {
      console.error(error);
      const errorMsg = error.message === "RATE_LIMIT"
        ? dict.avatar.rateLimited
        : dict.avatar.connectionError;
      setMessages(prev => [...prev, { role: "bot", content: errorMsg, uiOnly: true }]);
      if (!isMuted) {
        speak(errorMsg);
      } else {
        setIsSpeaking(false);
      }
    }
  };

  // Enter sends, Shift+Enter inserts a newline. isComposing guards IME input:
  // mid-composition Enter commits the candidate word and must not send.
  const handleInputKeyDown = (e) => {
    if (e.key !== "Enter" || e.shiftKey) return;
    if (e.nativeEvent?.isComposing) return;
    e.preventDefault();
    if (isListening) recognitionRef.current?.stop();
    handleSendText(inputText);
  };

  // Match the box to its content up to MAX_TEXTAREA_PX. Runs on every change,
  // including the reset to "" after sending, which shrinks it back to one row.
  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, MAX_TEXTAREA_PX)}px`;
  }, [inputText]);

  const handleFormSubmit = (e) => {
    e.preventDefault();
    if (isListening) {
      recognitionRef.current?.stop();
    }
    handleSendText(inputText);
  };

  // The job description and the result are both uiOnly, so neither is ever sent
  // back as chat history: a pasted job ad would blow the API's 2000-character
  // per-message limit, and it is not part of the conversation with the twin.
  const handleFitSubmit = async () => {
    const jd = fitText.trim();
    if (jd.length < FIT_MIN_CHARS) return;
    setFitOpen(false);
    setFitText("");
    setMessages(prev => [...prev, {
      role: "user",
      content: fill(dict.avatar.fitUserMessage, { n: new Intl.NumberFormat(lang).format(jd.length) }),
      uiOnly: true,
    }]);
    setIsSpeaking(true);
    try {
      const response = await fetch(`${apiBase()}/fit`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ job_description: jd, lang }),
      });
      if (!response.ok) throw new Error(response.status === 429 ? "RATE_LIMIT" : "FIT_ERROR");
      const data = await response.json();
      setMessages(prev => [...prev, { role: "bot", content: fitScoreLine(data, dict.avatar), fit: data, uiOnly: true }]);
    } catch (error) {
      console.error(error);
      setMessages(prev => [...prev, {
        role: "bot",
        content: error.message === "RATE_LIMIT" ? dict.avatar.rateLimited : dict.avatar.fitError,
        uiOnly: true,
      }]);
    } finally {
      setIsSpeaking(false);
    }
  };

  // Start with greeting audio when loaded (requires user interaction first usually, but we'll try)
  // Browsers usually block autoplay audio, so it's better to wait for the first click.

  return (
    <div ref={rootRef} className="avatar-root" style={{ backgroundColor: "#080C16", color: "white", display: "flex", flexDirection: "column", overflow: "hidden", fontFamily: "'Outfit', sans-serif" }}>

      {/* Subtle Dot Pattern Background */}
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, backgroundImage: "radial-gradient(rgba(255, 255, 255, 0.05) 1px, transparent 1px)", backgroundSize: "24px 24px", zIndex: 0, pointerEvents: "none" }} />

      {/* Top Nav — in normal flow so the layout below it is stable */}
      <div className="avatar-topnav" style={{ flexShrink: 0, height: "70px", zIndex: 10, display: "flex", justifyContent: "space-between", alignItems: "center", padding: "0 2rem", background: "rgba(8, 12, 22, 0.8)", backdropFilter: "blur(10px)", borderBottom: "1px solid rgba(255,255,255,0.05)" }}>
        <Link href={`/${lang}`} aria-label={dict.avatar.backToPortfolio} style={{ display: "flex", alignItems: "center", gap: "0.5rem", color: "rgba(255,255,255,0.7)", textDecoration: "none", fontSize: "0.9rem", fontWeight: 600, letterSpacing: "1px", transition: "color 0.2s" }}>
          <Home size={18} />
          <span className="avatar-back-label">{dict.avatar.backToPortfolio}</span>
        </Link>

        <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
          <input
            className="avatar-name-input"
            type="text"
            value={userName}
            onChange={(e) => handleNameChange(e.target.value)}
            placeholder={dict.avatar.namePlaceholder}
            aria-label={dict.avatar.nameLabel}
            maxLength={40}
            style={{
              width: "150px",
              background: "rgba(255,255,255,0.05)",
              border: "1px solid rgba(255,255,255,0.1)",
              borderRadius: "20px",
              color: "rgba(255,255,255,0.85)",
              padding: "0.4rem 0.9rem",
              fontSize: "0.85rem",
              outline: "none",
              fontFamily: "'Outfit', sans-serif"
            }}
          />
          <Link
            href={`/${otherLocale(lang)}/avatar`}
            aria-label={dict.nav.toggleLanguage}
            title={dict.nav.toggleLanguage}
            style={{ background: "rgba(255,255,255,0.05)", border: "1px solid rgba(255,255,255,0.1)", color: "rgba(255,255,255,0.7)", padding: "0.4rem 0.8rem", borderRadius: "20px", textDecoration: "none", fontSize: "0.8rem", fontWeight: 700, letterSpacing: "0.05em", fontFamily: "'JetBrains Mono', monospace", transition: "all 0.3s" }}
          >
            {otherLocale(lang).toUpperCase()}
          </Link>
          <button
            aria-label={isMuted ? dict.avatar.voiceDisabled : dict.avatar.voiceEnabled}
            title={isMuted ? dict.avatar.voiceDisabled : dict.avatar.voiceEnabled}
            onClick={() => {
              setIsMuted(!isMuted);
              if (!isMuted) {
                window.speechSynthesis.cancel();
                setIsSpeaking(false);
              }
            }}
            style={{ background: isMuted ? "rgba(255,255,255,0.05)" : "rgba(0, 242, 254, 0.1)", border: isMuted ? "1px solid rgba(255,255,255,0.1)" : "1px solid rgba(0, 242, 254, 0.3)", color: isMuted ? "rgba(255,255,255,0.6)" : "#00f2fe", padding: "0.4rem 1rem", borderRadius: "20px", cursor: "pointer", display: "flex", alignItems: "center", gap: "0.5rem", fontSize: "0.85rem", fontWeight: 600, transition: "all 0.3s" }}
          >
            {isMuted ? <VolumeX size={16} /> : <Volume2 size={16} />}
            <span className="avatar-voice-label">{isMuted ? dict.avatar.voiceDisabled : dict.avatar.voiceEnabled}</span>
          </button>
        </div>
      </div>

      {/* Frozen identity header: avatar + name + subtitle. Lives OUTSIDE the
          scroll area so it never moves while messages scroll underneath. */}
      <div className="avatar-header" style={{ flexShrink: 0, display: "flex", flexDirection: "column", alignItems: "center", padding: "1rem 1rem 0.75rem", zIndex: 5, background: "rgba(8, 12, 22, 0.9)", borderBottom: "1px solid rgba(255,255,255,0.04)" }}>
        <div className="avatar-viz-box" style={{ position: "relative", width: "110px", height: "110px", display: "flex", justifyContent: "center", alignItems: "center" }}>
          <motion.img
            className="avatar-viz-img"
            src="/salman-avatar.jpg"
            alt="Salman"
            animate={{ scale: isSpeaking ? [1, 1.05, 1] : isListening ? [1, 1.02, 1] : 1, boxShadow: isSpeaking ? "0 0 40px rgba(0, 242, 254, 0.6)" : "0 0 15px rgba(0, 242, 254, 0.2)" }}
            transition={{ duration: isSpeaking ? 0.8 : 1.5, repeat: Infinity }}
            style={{ width: "96px", height: "96px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", position: "relative", zIndex: 2, border: "3px solid rgba(0, 242, 254, 0.4)" }}
          />
          {isSpeaking && (
            <motion.div
              className="avatar-viz-pulse"
              animate={{ scale: [1, 1.3], opacity: [0.5, 0] }}
              transition={{ duration: 1, repeat: Infinity }}
              style={{ position: "absolute", width: "96px", height: "96px", borderRadius: "50%", background: "#00f2fe", zIndex: 1 }}
            />
          )}
        </div>
        <h2 className="avatar-title" style={{ fontSize: "1.1rem", fontWeight: 600, marginTop: "0.6rem", letterSpacing: "1px", color: "rgba(255,255,255,0.9)" }}>{dict.avatar.title}</h2>
        <p className="avatar-subtitle" style={{ fontSize: "0.8rem", color: "rgba(255,255,255,0.5)", marginTop: "0.2rem" }}>{dict.avatar.subtitle}</p>
      </div>

      {/* Scrollable messages — the ONLY thing that scrolls */}
      <div ref={chatScrollRef} className="avatar-chat-container" style={{ flex: 1, minHeight: 0, overflowY: "auto", padding: "1.25rem 2rem", display: "flex", flexDirection: "column", gap: "1.5rem", maxWidth: "800px", margin: "0 auto", width: "100%", scrollBehavior: "smooth", zIndex: 1 }}>

        {messages.map((msg, index) => (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            key={index}
            className="avatar-msg-row"
            style={{
              alignSelf: msg.role === "user" ? "flex-end" : "flex-start",
              maxWidth: msg.role === "user" ? "75%" : "90%",
              display: "flex",
              gap: "1rem",
              alignItems: "flex-start"
            }}
          >
            {msg.role === "bot" && (
               <img className="avatar-msg-icon" src="/salman-avatar.jpg" alt="AI" style={{ width: "32px", height: "32px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", flexShrink: 0, border: "1px solid rgba(0, 242, 254, 0.3)" }} />
            )}
            {msg.role === "user" && (
              /* Mirrors the twin's avatar on the other side. Shows the reader's
                 initials once they have given a name, and the localised "You"
                 until then. order:2 puts it after the bubble without needing a
                 second branch in the JSX. */
              <span
                className="avatar-msg-icon avatar-user-chip"
                title={userName || dict.avatar.you}
                style={{
                  order: 2,
                  flexShrink: 0,
                  width: "32px",
                  height: "32px",
                  borderRadius: "50%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  background: "rgba(0, 242, 254, 0.12)",
                  border: "1px solid rgba(0, 242, 254, 0.3)",
                  color: "#00f2fe",
                  fontSize: userName ? "0.75rem" : "0.65rem",
                  fontWeight: 700,
                  letterSpacing: "0.02em"
                }}
              >
                {userName ? initialsOf(userName) : dict.avatar.you}
              </span>
            )}

            {/* Column wrapper so the trace toggle can sit under the bubble without
                joining the row's flex layout beside the avatar icon. */}
            <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
            <div className={`avatar-message-bubble ${msg.role === "bot" ? "markdown-body" : ""}`} style={{
              padding: "1rem 1.5rem",
              borderRadius: "16px",
              background: msg.role === "user" ? "rgba(0, 242, 254, 0.08)" : "rgba(255, 255, 255, 0.03)",
              border: msg.role === "user" ? "1px solid rgba(0, 242, 254, 0.2)" : "1px solid rgba(255, 255, 255, 0.05)",
              borderBottomRightRadius: msg.role === "user" ? "4px" : "16px",
              borderBottomLeftRadius: msg.role === "bot" ? "4px" : "16px",
              fontSize: "1.05rem",
              lineHeight: 1.6,
              color: msg.role === "user" ? "#fff" : "rgba(255,255,255,0.85)",
              textAlign: "left",
              // Reader messages are rendered as plain text, so the newlines
              // Shift+Enter produces would otherwise collapse into spaces.
              whiteSpace: msg.role === "user" ? "pre-wrap" : undefined
            }}>
              {msg.fit ? (
                <FitCard fit={msg.fit} lang={lang} dict={dict} onDownload={fit => downloadFitPdf(fit, lang, dict.avatar)} />
              ) : msg.role === "bot" ? (
                <ReactMarkdown
                  remarkPlugins={[remarkGfm]}
                  components={{
                    // LLM output is untrusted: render links defensively so a
                    // prompt-injected URL can't masquerade as an endorsed link
                    // or run in this tab's context.
                    a: ({ node, ...props }) => (
                      <a {...props} target="_blank" rel="nofollow noopener noreferrer" />
                    ),
                  }}
                >
                  {msg.content}
                </ReactMarkdown>
              ) : (
                msg.content
              )}
            </div>
            {msg.trace && <TracePanel trace={msg.trace} lang={lang} dict={dict} />}
            </div>
          </motion.div>
        ))}

        {isSpeaking && messages[messages.length - 1]?.role === "user" && (
           <div style={{ alignSelf: "flex-start", display: "flex", gap: "1rem", maxWidth: "90%" }}>
             <img src="/salman-avatar.jpg" alt="AI" style={{ width: "30px", height: "30px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", flexShrink: 0, marginTop: "2px", border: "1px solid rgba(0, 242, 254, 0.3)" }} />
             <div style={{ padding: "1rem 0", display: "flex", gap: "6px", alignItems: "center" }}>
               <motion.div animate={{ opacity: [0.3, 1, 0.3] }} transition={{ duration: 1.4, repeat: Infinity }} style={{ width: "6px", height: "6px", background: "#00f2fe", borderRadius: "50%" }} />
               <motion.div animate={{ opacity: [0.3, 1, 0.3] }} transition={{ duration: 1.4, repeat: Infinity, delay: 0.2 }} style={{ width: "6px", height: "6px", background: "#00f2fe", borderRadius: "50%" }} />
               <motion.div animate={{ opacity: [0.3, 1, 0.3] }} transition={{ duration: 1.4, repeat: Infinity, delay: 0.4 }} style={{ width: "6px", height: "6px", background: "#00f2fe", borderRadius: "50%" }} />
             </div>
           </div>
        )}
      </div>

      {/* Suggestion Pills */}
      {messages.length === 1 && !isSpeaking && (
        <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "0.8rem", width: "100%", maxWidth: "800px", margin: "0 auto", padding: "0 2rem", marginBottom: "1rem", zIndex: 10 }}>
          <button onClick={() => handleSendText(dict.avatar.suggestions[0])} style={{ fontSize: "0.9rem", padding: "0.6rem 1.2rem", borderRadius: "20px", background: "var(--glass-bg)", border: "1px solid var(--glass-border)", color: "var(--text-primary)", cursor: "pointer", transition: "all 0.2s", fontFamily: "inherit" }} onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0, 242, 254, 0.1)"; e.currentTarget.style.borderColor = "rgba(0, 242, 254, 0.3)" }} onMouseOut={(e) => { e.currentTarget.style.background = "var(--glass-bg)"; e.currentTarget.style.borderColor = "var(--glass-border)" }}>
            {dict.avatar.suggestions[0]}
          </button>
          <button onClick={() => handleSendText(dict.avatar.suggestions[1])} style={{ fontSize: "0.9rem", padding: "0.6rem 1.2rem", borderRadius: "20px", background: "var(--glass-bg)", border: "1px solid var(--glass-border)", color: "var(--text-primary)", cursor: "pointer", transition: "all 0.2s", fontFamily: "inherit" }} onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0, 242, 254, 0.1)"; e.currentTarget.style.borderColor = "rgba(0, 242, 254, 0.3)" }} onMouseOut={(e) => { e.currentTarget.style.background = "var(--glass-bg)"; e.currentTarget.style.borderColor = "var(--glass-border)" }}>
            {dict.avatar.suggestions[1]}
          </button>
          <button onClick={() => handleSendText(dict.avatar.suggestions[2])} style={{ fontSize: "0.9rem", padding: "0.6rem 1.2rem", borderRadius: "20px", background: "var(--glass-bg)", border: "1px solid var(--glass-border)", color: "var(--text-primary)", cursor: "pointer", transition: "all 0.2s", fontFamily: "inherit" }} onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0, 242, 254, 0.1)"; e.currentTarget.style.borderColor = "rgba(0, 242, 254, 0.3)" }} onMouseOut={(e) => { e.currentTarget.style.background = "var(--glass-bg)"; e.currentTarget.style.borderColor = "var(--glass-border)" }}>
            {dict.avatar.suggestions[2]}
          </button>
        </div>
      )}

      {/* Input Area */}
      <div className="avatar-input-wrapper" style={{ padding: "0 2rem 2rem 2rem", zIndex: 10, display: "flex", justifyContent: "center", flexDirection: "column", alignItems: "center" }}>
        <form onSubmit={handleFormSubmit} style={{ display: "flex", gap: "0.5rem", maxWidth: "800px", width: "100%", alignItems: "flex-end", background: "#0D1322", padding: "0.6rem 0.6rem 0.6rem 1.5rem", borderRadius: "16px", border: "1px solid rgba(255,255,255,0.1)", boxShadow: "0 10px 30px rgba(0,0,0,0.5)" }}>

          <textarea
            ref={textareaRef}
            rows={1}
            maxLength={MAX_MESSAGE_CHARS}
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            onKeyDown={handleInputKeyDown}
            placeholder={isListening ? dict.avatar.listening : dict.avatar.placeholder}
            style={{
              flex: 1,
              background: "transparent",
              border: "none",
              color: "#fff",
              fontSize: "1.05rem",
              outline: "none",
              fontFamily: "'Outfit', sans-serif",
              // Grown to fit by autoGrow(); resize is disabled so the drag
              // handle cannot fight the app shell's fixed height.
              resize: "none",
              overflowY: "auto",
              lineHeight: 1.5,
              maxHeight: `${MAX_TEXTAREA_PX}px`,
              padding: 0
            }}
          />

          {/* Job fit lives in the input bar, beside the mic, like an attach
              button: always reachable, never floating over the conversation,
              and deliberately not mixed in with the sample questions. */}
          <button
            type="button"
            className="fit-icon-btn"
            onClick={() => setFitOpen(true)}
            disabled={isSpeaking}
            aria-label={dict.avatar.fitButton}
            title={dict.avatar.fitButton}
          >
            <Briefcase size={20} />
          </button>

          <button
            type="button"
            onClick={toggleListening}
            style={{
              background: "transparent",
              border: "none",
              color: isListening ? "#f43f5e" : "rgba(255,255,255,0.4)",
              cursor: "pointer",
              padding: "0.5rem",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              transition: "color 0.3s"
            }}
            aria-label={isListening ? dict.avatar.stopListening : dict.avatar.startListening}
          >
            {isListening ? <Mic size={22} /> : <MicOff size={22} />}
          </button>

          <button
            type="submit"
            disabled={!inputText.trim()}
            style={{
              background: inputText.trim() ? "linear-gradient(135deg, #00f2fe, #4facfe)" : "rgba(255,255,255,0.05)",
              color: inputText.trim() ? "#000" : "rgba(255,255,255,0.2)",
              border: "none",
              borderRadius: "12px",
              padding: "0.6rem",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              cursor: inputText.trim() ? "pointer" : "not-allowed",
              transition: "all 0.3s"
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="19" x2="12" y2="5"></line><polyline points="5 12 12 5 19 12"></polyline></svg>
          </button>
        </form>

        {/* Discoverability for the shortcut. Hidden on touch layouts, where
            there is no Shift key and vertical space is scarce. */}
        <p className="avatar-kbd-hint">
          <kbd>Enter</kbd> {dict.avatar.hintSend}
          <span className="avatar-kbd-sep">·</span>
          <kbd>Shift</kbd>+<kbd>Enter</kbd> {dict.avatar.hintNewline}
        </p>
      </div>

      {/* Footer text */}
      <div style={{ textAlign: "center", paddingBottom: "1rem", color: "rgba(255,255,255,0.3)", fontSize: "0.75rem", zIndex: 10 }}>
        {dict.avatar.disclaimer}
      </div>

      {fitOpen && (
        <div
          className="fit-backdrop"
          role="dialog"
          aria-modal="true"
          aria-labelledby="fit-title"
          onClick={(e) => { if (e.target === e.currentTarget) setFitOpen(false); }}
          onKeyDown={(e) => { if (e.key === "Escape") setFitOpen(false); }}
        >
          <div className="fit-modal">
            <h3 id="fit-title">{dict.avatar.fitTitle}</h3>
            <p>{dict.avatar.fitIntro}</p>
            <textarea
              className="fit-input"
              autoFocus
              value={fitText}
              maxLength={FIT_MAX_CHARS}
              onChange={(e) => setFitText(e.target.value)}
              placeholder={dict.avatar.fitPlaceholder}
            />
            <div className="fit-modal-row">
              <span className="fit-count">
                {fitText.trim().length < FIT_MIN_CHARS
                  ? fill(dict.avatar.fitMinChars, { n: FIT_MIN_CHARS })
                  : `${new Intl.NumberFormat(lang).format(fitText.length)} / ${new Intl.NumberFormat(lang).format(FIT_MAX_CHARS)}`}
              </span>
              <button type="button" className="fit-cancel" onClick={() => setFitOpen(false)}>{dict.avatar.fitCancel}</button>
              <button
                type="button"
                className="fit-submit"
                disabled={fitText.trim().length < FIT_MIN_CHARS}
                onClick={handleFitSubmit}
              >
                {dict.avatar.fitAnalyze}
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
