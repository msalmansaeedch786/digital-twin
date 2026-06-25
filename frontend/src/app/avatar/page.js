"use client";

import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Mic, MicOff, Home, Volume2, VolumeX } from "lucide-react";
import Link from "next/link";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

export default function AvatarMode() {
  const [isListening, setIsListening] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [isMuted, setIsMuted] = useState(true); // Default to muted so it doesn't auto-play
  const [inputText, setInputText] = useState("");
  const [messages, setMessages] = useState([
    { role: "bot", content: "Hello. I am Salman's Digital Twin. Speak into the microphone or type a message below." }
  ]);
  const [voices, setVoices] = useState([]);

  const recognitionRef = useRef(null);
  const messagesEndRef = useRef(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

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
      recognition.lang = 'en-US';

      recognition.onresult = (event) => {
        let currentTranscript = "";
        for (let i = event.resultIndex; i < event.results.length; i++) {
          currentTranscript += event.results[i][0].transcript;
        }
        setInputText(currentTranscript);
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
  }, []);

  const toggleListening = () => {
    if (!recognitionRef.current) {
      alert("Speech recognition is not supported in this browser. Try Chrome or Edge.");
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

    // Try to find a good English male voice
    const preferredVoice = voices.find(v =>
      v.lang.includes('en-') && (v.name.includes('Male') || v.name.includes('Google UK English Male') || v.name.includes('Daniel'))
    );
    if (preferredVoice) {
      utterance.voice = preferredVoice;
    }

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
      const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
      const response = await fetch(`${apiUrl}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // Send previous messages as history so AI remembers the context
        body: JSON.stringify({
          message: userMsg,
          history: messages.map(m => ({ role: m.role, content: m.content }))
        }),
      });

      if (!response.ok) throw new Error("Network error");

      const data = await response.json();
      setMessages(prev => [...prev, { role: "bot", content: data.reply }]);
      if (!isMuted) {
        speak(data.reply);
      } else {
        setIsSpeaking(false);
      }
    } catch (error) {
      console.error(error);
      const errorMsg = "Sorry, I lost my connection to the brain.";
      setMessages(prev => [...prev, { role: "bot", content: errorMsg }]);
      if (!isMuted) {
        speak(errorMsg);
      } else {
        setIsSpeaking(false);
      }
    }
  };

  const handleFormSubmit = (e) => {
    e.preventDefault();
    if (isListening) {
      recognitionRef.current?.stop();
    }
    handleSendText(inputText);
  };

  // Start with greeting audio when loaded (requires user interaction first usually, but we'll try)
  // Browsers usually block autoplay audio, so it's better to wait for the first click.

  return (
    <div style={{ backgroundColor: "#080C16", height: "100vh", color: "white", display: "flex", flexDirection: "column", overflow: "hidden", position: "relative", fontFamily: "'Outfit', sans-serif" }}>

      {/* Subtle Dot Pattern Background */}
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, backgroundImage: "radial-gradient(rgba(255, 255, 255, 0.05) 1px, transparent 1px)", backgroundSize: "24px 24px", zIndex: 0, pointerEvents: "none" }} />

      {/* Top Nav */}
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: "70px", zIndex: 10, display: "flex", justifyContent: "space-between", alignItems: "center", padding: "0 2rem", background: "rgba(8, 12, 22, 0.8)", backdropFilter: "blur(10px)", borderBottom: "1px solid rgba(255,255,255,0.05)" }}>
        <Link href="/" style={{ display: "flex", alignItems: "center", gap: "0.5rem", color: "rgba(255,255,255,0.7)", textDecoration: "none", fontSize: "0.9rem", fontWeight: 600, letterSpacing: "1px", transition: "color 0.2s" }}>
          <Home size={18} />
          <span>PORTFOLIO</span>
        </Link>

        <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
          <button
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
            <span>{isMuted ? "Voice Disabled" : "Voice Enabled"}</span>
          </button>
        </div>
      </div>

      {/* ChatGPT-style Chat History */}
      <div className="avatar-chat-container" style={{ flex: 1, overflowY: "auto", padding: "100px 2rem 2rem 2rem", display: "flex", flexDirection: "column", gap: "2rem", maxWidth: "800px", margin: "0 auto", width: "100%", scrollBehavior: "smooth", zIndex: 1 }}>

        {/* The elegant minimal visualizer at the top of the chat */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: "2rem" }}>
          <div style={{ position: "relative", width: "140px", height: "140px", display: "flex", justifyContent: "center", alignItems: "center" }}>
            <motion.img
              src="/salman-avatar.jpg"
              alt="Salman"
              animate={{ scale: isSpeaking ? [1, 1.05, 1] : isListening ? [1, 1.02, 1] : 1, boxShadow: isSpeaking ? "0 0 40px rgba(0, 242, 254, 0.6)" : "0 0 15px rgba(0, 242, 254, 0.2)" }}
              transition={{ duration: isSpeaking ? 0.8 : 1.5, repeat: Infinity }}
              style={{ width: "120px", height: "120px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", position: "relative", zIndex: 2, border: "3px solid rgba(0, 242, 254, 0.4)" }}
            />
            {isSpeaking && (
              <motion.div
                animate={{ scale: [1, 1.3], opacity: [0.5, 0] }}
                transition={{ duration: 1, repeat: Infinity }}
                style={{ position: "absolute", width: "120px", height: "120px", borderRadius: "50%", background: "#00f2fe", zIndex: 1 }}
              />
            )}
          </div>
          <h2 style={{ fontSize: "1.2rem", fontWeight: 600, marginTop: "1rem", letterSpacing: "1px", color: "rgba(255,255,255,0.9)" }}>Salman's Digital Twin</h2>
          <p style={{ fontSize: "0.85rem", color: "rgba(255,255,255,0.5)", marginTop: "0.3rem" }}>AI-Powered Professional Assistant</p>
        </div>

        {messages.map((msg, index) => (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            key={index}
            style={{
              alignSelf: msg.role === "user" ? "flex-end" : "flex-start",
              maxWidth: msg.role === "user" ? "75%" : "90%",
              display: "flex",
              gap: "1rem",
              alignItems: "flex-start"
            }}
          >
            {msg.role === "bot" && (
               <img src="/salman-avatar.jpg" alt="AI" style={{ width: "32px", height: "32px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", flexShrink: 0, border: "1px solid rgba(0, 242, 254, 0.3)" }} />
            )}

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
              textAlign: "left"
            }}>
              {msg.role === "bot" ? (
                <ReactMarkdown remarkPlugins={[remarkGfm]}>
                  {msg.content}
                </ReactMarkdown>
              ) : (
                msg.content
              )}
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
        <div ref={messagesEndRef} />
      </div>

      {/* Suggestion Pills */}
      {messages.length === 1 && !isSpeaking && (
        <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "0.8rem", width: "100%", maxWidth: "800px", margin: "0 auto", padding: "0 2rem", marginBottom: "1rem", zIndex: 10 }}>
          <button onClick={() => handleSendText("What is your core tech stack?")} style={{ fontSize: "0.9rem", padding: "0.6rem 1.2rem", borderRadius: "20px", background: "var(--glass-bg)", border: "1px solid var(--glass-border)", color: "var(--text-primary)", cursor: "pointer", transition: "all 0.2s", fontFamily: "inherit" }} onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0, 242, 254, 0.1)"; e.currentTarget.style.borderColor = "rgba(0, 242, 254, 0.3)" }} onMouseOut={(e) => { e.currentTarget.style.background = "var(--glass-bg)"; e.currentTarget.style.borderColor = "var(--glass-border)" }}>
            What is your core tech stack?
          </button>
          <button onClick={() => handleSendText("Tell me about your AWS experience")} style={{ fontSize: "0.9rem", padding: "0.6rem 1.2rem", borderRadius: "20px", background: "var(--glass-bg)", border: "1px solid var(--glass-border)", color: "var(--text-primary)", cursor: "pointer", transition: "all 0.2s", fontFamily: "inherit" }} onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0, 242, 254, 0.1)"; e.currentTarget.style.borderColor = "rgba(0, 242, 254, 0.3)" }} onMouseOut={(e) => { e.currentTarget.style.background = "var(--glass-bg)"; e.currentTarget.style.borderColor = "var(--glass-border)" }}>
            Tell me about your AWS experience
          </button>
          <button onClick={() => handleSendText("How do you approach cloud security?")} style={{ fontSize: "0.9rem", padding: "0.6rem 1.2rem", borderRadius: "20px", background: "var(--glass-bg)", border: "1px solid var(--glass-border)", color: "var(--text-primary)", cursor: "pointer", transition: "all 0.2s", fontFamily: "inherit" }} onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0, 242, 254, 0.1)"; e.currentTarget.style.borderColor = "rgba(0, 242, 254, 0.3)" }} onMouseOut={(e) => { e.currentTarget.style.background = "var(--glass-bg)"; e.currentTarget.style.borderColor = "var(--glass-border)" }}>
            How do you approach cloud security?
          </button>
        </div>
      )}

      {/* Input Area */}
      <div className="avatar-input-wrapper" style={{ padding: "0 2rem 2rem 2rem", zIndex: 10, display: "flex", justifyContent: "center", flexDirection: "column", alignItems: "center" }}>
        <form onSubmit={handleFormSubmit} style={{ display: "flex", gap: "0.5rem", maxWidth: "800px", width: "100%", alignItems: "center", background: "#0D1322", padding: "0.6rem 0.6rem 0.6rem 1.5rem", borderRadius: "16px", border: "1px solid rgba(255,255,255,0.1)", boxShadow: "0 10px 30px rgba(0,0,0,0.5)" }}>

          <input
            type="text"
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            placeholder={isListening ? "Listening..." : "Message Salman's twin..."}
            style={{
              flex: 1,
              background: "transparent",
              border: "none",
              color: "#fff",
              fontSize: "1.05rem",
              outline: "none",
              fontFamily: "'Outfit', sans-serif"
            }}
          />

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
            aria-label={isListening ? "Stop listening" : "Start listening"}
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
      </div>

      {/* Footer text */}
      <div style={{ textAlign: "center", paddingBottom: "1rem", color: "rgba(255,255,255,0.3)", fontSize: "0.75rem", zIndex: 10 }}>
        AI can make mistakes. Consider verifying important information.
      </div>

    </div>
  );
}
