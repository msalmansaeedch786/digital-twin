"use client";

import { useState, useRef, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Tilt from "react-parallax-tilt";
import { Sun, Moon, Mail, Award, ExternalLink, MessageSquare, MapPin } from "lucide-react";
import { FiGithub, FiLinkedin, FiYoutube } from "react-icons/fi";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { otherLocale } from "../dictionaries/locales";
// Single source of truth: scripts/generate_certifications.py derives the list
// in data/05_certifications.txt from this same file, so the twin and the badge
// cards cannot disagree about which credentials are held.
import certificationsData from "../certifications.json";

export default function PortfolioClient({ lang, dict }) {
  const [theme, setTheme] = useState("light");
  const [typed, setTyped] = useState("");
  const pathname = usePathname();
  const certifications = certificationsData.certifications;

  // Terminal wordmark: the prompt "~/muhammad-salman:" stays fixed while these
  // messages type out after it, cycling like a live shell.
  const WORDMARK_MESSAGES = dict.wordmark;

  // Swap only the leading locale segment so the toggle keeps the reader on the
  // page they are already on (/de/avatar <-> /en/avatar).
  const switchLocaleHref = (pathname || `/${lang}`).replace(
    new RegExp(`^/${lang}(?=/|$)`),
    `/${otherLocale(lang)}`
  );

  useEffect(() => {
    // Respect reduced-motion: no animation, just show the welcome
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setTyped(WORDMARK_MESSAGES[0]);
      return;
    }

    let timer;
    let i = 0;
    let phrase = 0;
    let deleting = false;

    const tick = () => {
      const current = WORDMARK_MESSAGES[phrase];
      if (!deleting) {
        i += 1;
        setTyped(current.slice(0, i));
        if (i === current.length) {
          deleting = true;
          timer = setTimeout(tick, 4200); // let the message be read
          return;
        }
        timer = setTimeout(tick, 75);
      } else {
        i -= 1;
        setTyped(current.slice(0, i));
        if (i === 0) {
          deleting = false;
          phrase = (phrase + 1) % WORDMARK_MESSAGES.length;
          timer = setTimeout(tick, 500);
          return;
        }
        timer = setTimeout(tick, 35);
      }
    };

    timer = setTimeout(tick, 600);
    return () => clearTimeout(timer);
    // Re-run on language change so the wordmark retypes in the new language.
  }, [WORDMARK_MESSAGES]);

  useEffect(() => {
    // Read theme from localStorage or default to light (the chat page forces dark)
    const savedTheme = localStorage.getItem("theme") || "light";
    setTheme(savedTheme);
    document.documentElement.setAttribute("data-theme", savedTheme);
  }, []);

  const toggleTheme = () => {
    const newTheme = theme === "dark" ? "light" : "dark";
    setTheme(newTheme);
    document.documentElement.setAttribute("data-theme", newTheme);
    localStorage.setItem("theme", newTheme);
  };

  // Company names and dates are the same in every language, so they stay here
  // and only the translated fields are merged in from the dictionary.
  //
  // Merged by SLUG, not by array position. These lists used to be zipped with
  // dict.experiences[i], which silently coupled three files to each other by
  // order: inserting one job at the top shifted every German role label by one,
  // with no error and no failing test — the page simply attributed the wrong role
  // to the wrong employer. mergeBySlug throws instead, so a mismatch is a build
  // failure rather than a wrong CV in two languages.
  const mergeBySlug = (rows, translations, label) =>
    rows.map(({ slug, ...rest }) => {
      const t = translations[slug];
      if (!t) {
        throw new Error(
          `${label}: no "${slug}" in the ${lang} dictionary. ` +
          `Add it to BOTH en.json and de.json — they must stay key-parallel.`
        );
      }
      return { slug, ...rest, ...t };
    });

  const experiences = mergeBySlug([
    { slug: "thoughtworks", company: "Thoughtworks", date: "April 2022 - Present" },
    { slug: "receeve", company: "receeve GmbH", date: "Jun 2021 - Nov 2022" },
    { slug: "orbem", company: "Orbem", date: "Oct 2021 - Dec 2021" },
    { slug: "zameen", company: "Zameen.com", date: "Jan 2021 - Jun 2021" },
    { slug: "northbay-solutions", company: "NorthBay Solutions", date: "Jul 2019 - Dec 2020" },
    { slug: "ai-research-lab", company: "AI & Multidisciplinary Research Lab", date: "Jan 2019 - Jun 2019" },
    { slug: "automata", company: "AUTOMATA THE PLATFORM", date: "Aug 2018 - Jan 2019" }
  ], dict.experiences, "experiences");

  const projects = mergeBySlug([
    { slug: "mercedes-otr", title: "Mercedes-Benz AG - OTR", date: "Apr 2025 - Present", tech: ["Kubernetes", "AWS", "AI Integration"] },
    { slug: "mbition-runners", title: "MBition - SWF Gitlab CI Runners", date: "Jul 2023 - Jan 2025", tech: ["Terraform", "Packer", "AWS EC2"] },
    { slug: "porsche-infra", title: "Porsche AG - Cloud Infrastructure", date: "Jan 2023 - Jun 2023", tech: ["AWS", "Terraform", "GitHub Actions"] },
    { slug: "dealermeter", title: "DealerMeter", date: "Mar 2021 - Apr 2021", tech: ["AWS Lambda", "AWS Glue", "Athena"] },
    { slug: "vector-solutions", title: "Vector Solutions", date: "Dec 2019 - Dec 2020", tech: ["AWS FSx", "AWS Transfer for SFTP", "Sysprep AMIs", "Octopus Deploy"] },
    { slug: "amway", title: "Amway", date: "Sep 2019 - Dec 2019", tech: ["Elastic Beanstalk", "ECS Fargate", "Jenkins", "Oracle"] },
    { slug: "northbay-labs", title: "NorthBay Labs", date: "Jul 2019 - Sep 2019", tech: ["ELK Stack", "Grafana", "AWS SAM", "Linux Shell Scripting"] },
    { slug: "codefreak", title: "CodeFreak Programming Platform", date: "Jan 2019 - Jun 2019", tech: ["Angular 6", "ASP.NET Core", "Docker"] },
    { slug: "keyless", title: "Keyless Decentralized Network", date: "Aug 2018 - Jan 2019", tech: ["Ethereum", "Smart Contracts", "Biometrics"] }
  ], dict.projects, "projects");

  const education = mergeBySlug([
    { slug: "pucit", school: "University of the Punjab (PUCIT)", date: "Oct 2015 - Jun 2019" },
    { slug: "punjab-colleges", school: "Punjab Group of Colleges", date: "Sep 2012 - Sep 2014" },
    { slug: "educators", school: "The Educators", date: "Jan 2010 - Dec 2012" }
  ], dict.education, "education");


  return (
    <>
      {/* Background Ambient Orbs */}
      <div className="ambient-orb orb-1"></div>
      <div className="ambient-orb orb-2"></div>
      <div className="ambient-orb orb-3"></div>

      {/* Navigation Bar */}
      <nav className="navbar">
        <Link href={`/${lang}`} className="wordmark" aria-label={dict.nav.home}>
          <span className="prompt">~/</span>muhammad-salman<span className="prompt">:</span>
          <span className="typed-msg">&nbsp;{typed}</span><span className="cursor" />
        </Link>
        <div className="nav-links">
          <a href="#experience" className="nav-link">{dict.nav.experience}</a>
          <a href="#education" className="nav-link">{dict.nav.education}</a>
          <a href="#projects" className="nav-link">{dict.nav.projects}</a>
          <a href="#certifications" className="nav-link">{dict.nav.certifications}</a>
          <Link href={`/${lang}/avatar`} className="nav-link text-accent" style={{ fontWeight: 600 }}>{dict.nav.digitalTwin}</Link>
          {/* A plain <a>, not <Link>, on purpose. Switching locale swaps the
              [lang] root layout, and Next's soft-navigation scroll handler
              picks the wrong node for that case: arriving from the top of /en
              it landed the reader ~6100px down /de, in the footer. A real
              document navigation always starts at the top, and a locale switch
              is a new document anyway — both pages are static and edge-cached,
              so the reload is cheap. */}
          <a
            href={switchLocaleHref}
            className="lang-toggle"
            aria-label={dict.nav.toggleLanguage}
            title={dict.nav.toggleLanguage}
          >
            {otherLocale(lang).toUpperCase()}
          </a>
          <button onClick={toggleTheme} className="theme-toggle" aria-label={dict.nav.toggleTheme}>
            {theme === "dark" ? <Sun size={20} /> : <Moon size={20} />}
          </button>
        </div>
      </nav>

      <div className="container">

        {/* HERO SECTION */}
        <section id="home" className="section" style={{ paddingTop: "6rem", minHeight: "80vh", display: "flex", alignItems: "center" }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(350px, 1fr))", gap: "4rem", width: "100%", alignItems: "center" }}>

            {/* LEFT COLUMN: Main Intro */}
            <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8 }}>
              <h1>{dict.hero.greeting} <span className="text-accent">Muhammad Salman</span></h1>
              <h2 style={{ fontSize: "1.8rem", marginBottom: "1.25rem" }}>{dict.hero.role}</h2>
              <div className="hero-meta">
                <span className="meta-chip"><MapPin size={15} /> {dict.hero.location}</span>
                <span className="meta-chip"><Award size={15} /> {dict.hero.certBadge}</span>
              </div>
              <p style={{ maxWidth: "600px", fontSize: "1.15rem", marginBottom: "0.5rem", lineHeight: 1.7 }}>
                {dict.hero.summary}</p>
              <div className="hero-contact">
                <a href="mailto:msalmansaeedch786@gmail.com" className="contact-btn"><Mail size={18} /> {dict.common.email}</a>
                <a href="https://github.com/msalmansaeedch" target="_blank" rel="noreferrer" className="contact-btn"><FiGithub size={18} /> GitHub</a>
                <a href="https://linkedin.com/in/msalmansaeedch" target="_blank" rel="noreferrer" className="contact-btn"><FiLinkedin size={18} /> LinkedIn</a>
                <a href="https://www.youtube.com/@msalmansaeedch" target="_blank" rel="noreferrer" className="contact-btn"><FiYoutube size={18} /> YouTube</a>
              </div>
            </motion.div>

            {/* RIGHT COLUMN: Digital Twin Widget */}
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.8, delay: 0.2 }}
              style={{
                position: "relative",
                background: "var(--accent-soft-bg)",
                border: "1px solid var(--accent-soft-border)",
                borderRadius: "24px",
                padding: "2.5rem 2rem",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                textAlign: "center",
                boxShadow: "0 10px 30px -10px var(--neon-cyan-glow)",
                backdropFilter: "blur(10px)",
                maxWidth: "500px",
                margin: "0 auto"
              }}
            >
              <span className="online-pill"><span className="online-dot" />{dict.twin.online}</span>
              <img
                src="/salman-avatar.jpg"
                alt={dict.twin.avatarAlt}
                style={{ width: "90px", height: "90px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", border: "2px solid var(--accent-soft-border)", marginBottom: "1.5rem" }}
              />
              <h3 style={{ fontSize: "1.6rem", fontWeight: 500, marginBottom: "0.5rem", letterSpacing: "0.5px" }}>
                {dict.twin.headlineBefore}<span style={{ fontStyle: "italic", color: "var(--neon-cyan)", fontWeight: 600 }}>{dict.twin.headlineAccent}</span>.
              </h3>
              <p style={{ fontSize: "1.2rem", fontWeight: 400, marginBottom: "1rem", lineHeight: 1.4 }}>
                {dict.twin.tagline}
              </p>
              <p style={{ fontSize: "0.95rem", color: "var(--text-secondary)", marginBottom: "2rem", maxWidth: "90%" }}>
                {dict.twin.blurb}
              </p>

              <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "0.8rem", width: "100%" }}>
                <Link href={`/${lang}/avatar`} style={{ fontSize: "1rem", fontWeight: 600, padding: "0.8rem 1.8rem", borderRadius: "25px", background: "linear-gradient(135deg, #00f2fe, #4facfe)", border: "none", color: "#000", textDecoration: "none", transition: "all 0.2s", marginTop: "0.5rem", display: "flex", alignItems: "center", gap: "0.5rem" }} onMouseOver={(e) => { e.currentTarget.style.transform = "translateY(-2px)"; e.currentTarget.style.boxShadow = "0 4px 15px rgba(0, 242, 254, 0.4)" }} onMouseOut={(e) => { e.currentTarget.style.transform = "translateY(0)"; e.currentTarget.style.boxShadow = "none" }}>
                  <MessageSquare size={20} />
                  {dict.twin.cta}
                </Link>
              </div>
            </motion.div>

          </div>
        </section>

        {/* EXPERIENCE SECTION */}
        <section id="experience" className="section">
          <h2>{dict.sections.experience}</h2>
          <div className="timeline">
            {experiences.map((exp, index) => (
              <motion.div
                key={index}
                className="timeline-item"
                initial={{ opacity: 0, x: -50 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: "-100px" }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
              >
                <div className="timeline-dot"></div>
                <div className="timeline-date">{exp.date}</div>
                <div className="timeline-title" style={{ fontSize: "1.4rem", fontWeight: "bold", color: "var(--neon-cyan)" }}>{exp.company}</div>
                <div className="timeline-company" style={{ fontSize: "1.1rem", marginBottom: "0.5rem" }}>{exp.role}</div>
                <p>{exp.details}</p>
              </motion.div>
            ))}
          </div>
        </section>

        {/* EDUCATION SECTION */}
        <section id="education" className="section">
          <h2>{dict.sections.education}</h2>
          <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
            {education.map((edu, index) => (
              <motion.div
                key={index}
                className="glass-panel"
                style={{ padding: "2rem" }}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: index * 0.1 }}
              >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "1rem" }}>
                  <div>
                    <h3 style={{ fontSize: "1.3rem", marginBottom: "0.5rem", color: "var(--text-primary)" }}>{edu.degree}</h3>
                    <p style={{ color: "var(--text-secondary)", fontWeight: 600, fontSize: "1.1rem", margin: 0 }}>{edu.school}</p>
                  </div>
                  <div style={{ textAlign: "right" }}>
                    <div style={{ color: "var(--neon-cyan)", fontFamily: "'JetBrains Mono', monospace", marginBottom: "0.5rem", fontSize: "0.9rem", letterSpacing: "1px" }}>{edu.date}</div>
                    <span style={{ background: "rgba(0, 242, 254, 0.1)", color: "var(--neon-cyan)", padding: "0.2rem 0.8rem", borderRadius: "20px", fontSize: "0.8rem", fontWeight: 600 }}>{edu.grade}</span>
                  </div>
                </div>
              </motion.div>
            ))}
          </div>
        </section>

        {/* PROJECTS SECTION */}
        <section id="projects" className="section">
          <h2>{dict.sections.projects}</h2>
          <div className="projects-grid">
            {projects.map((project, index) => (
              <Tilt key={index} tiltMaxAngleX={5} tiltMaxAngleY={5} scale={1.02} transitionSpeed={2000}>
                <motion.div
                  className="project-card glass-panel"
                  initial={{ opacity: 0, scale: 0.9 }}
                  whileInView={{ opacity: 1, scale: 1 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.4, delay: index * 0.1 }}
                >
                  <div style={{ padding: "2rem" }}>
                    <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginBottom: "0.5rem", fontFamily: "'JetBrains Mono', monospace", letterSpacing: "1px" }}>{project.date}</div>
                    <h3 style={{ margin: "0 0 1rem 0", color: "var(--neon-cyan)" }}>{project.title}</h3>
                    <p>{project.desc}</p>
                    {project.tech && (
                      <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap", marginTop: "1rem" }}>
                        {project.tech.map((t, i) => (
                          <span key={i} style={{ background: "rgba(0, 242, 254, 0.1)", color: "var(--neon-cyan)", padding: "0.2rem 0.6rem", borderRadius: "12px", fontSize: "0.8rem", border: "1px solid rgba(0, 242, 254, 0.3)" }}>
                            {t}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </motion.div>
              </Tilt>
            ))}
          </div>
        </section>

        {/* CERTIFICATIONS SECTION */}
        <section id="certifications" className="section">
          <h2>{dict.sections.certifications}</h2>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "1.5rem" }}>
            {certifications.map((cert, index) => {
              // Not every credential has a public verification page. A card
              // without `url` renders as a plain element rather than an anchor
              // with href={undefined}, which would look clickable, be focusable
              // and go nowhere. The external-link glyph is dropped with it, so
              // the card does not advertise a link it does not have.
              const CardTag = cert.url ? motion.a : motion.div;
              const linkProps = cert.url
                ? { href: cert.url, target: "_blank", rel: "noreferrer" }
                : {};
              return (
              <CardTag
                {...linkProps}
                key={index}
                className="glass-panel"
                style={{ padding: "2rem", display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", textDecoration: "none", color: "var(--text-primary)", position: "relative" }}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                whileHover={{ scale: 1.03, borderColor: "var(--neon-cyan)" }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: index * 0.05 }}
              >
                {cert.url && (
                  <div style={{ position: "absolute", top: "1rem", right: "1rem" }}>
                    <ExternalLink size={20} style={{ color: "var(--text-secondary)" }} />
                  </div>
                )}
                <img src={cert.image} alt={cert.title} style={{ width: "150px", height: "150px", objectFit: "contain", filter: "var(--badge-shadow)", marginBottom: "1.25rem" }} />
                <span style={{ background: "rgba(0, 242, 254, 0.1)", color: "var(--neon-cyan)", padding: "0.3rem 0.8rem", borderRadius: "20px", fontSize: "0.75rem", fontWeight: 600, letterSpacing: "1px", textTransform: "uppercase", marginBottom: "1rem" }}>
                  {dict.certLevels[cert.type] ?? cert.type}
                </span>
                <h3 style={{ margin: "0 0 0.5rem 0", fontSize: "1.1rem", lineHeight: 1.4 }}>{cert.title}</h3>
                <p style={{ margin: 0, color: "var(--text-secondary)", fontSize: "0.85rem", fontWeight: 600 }}>{cert.issuer}</p>
              </CardTag>
              );
            })}
          </div>
        </section>

      </div>

      {/* Main Call to Action: Talk to Digital Twin */}
      <div style={{ display: "flex", justifyContent: "center", padding: "4rem 0 6rem 0" }}>
        <Link href={`/${lang}/avatar`} style={{ textDecoration: "none" }}>
          <motion.div
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            style={{
              background: "linear-gradient(135deg, var(--neon-cyan), var(--neon-purple))",
              padding: "1rem 2rem",
              borderRadius: "50px",
              color: "#fff",
              fontWeight: 800,
              fontSize: "1.2rem",
              boxShadow: "0 10px 30px var(--neon-purple-glow)",
              display: "flex",
              alignItems: "center",
              gap: "1rem"
            }}
          >
            <div style={{ width: "20px", height: "20px", borderRadius: "50%", background: "#fff", animation: "pulse 2s infinite" }} />
            {dict.hero.cta}
          </motion.div>
        </Link>
      </div>

      {/* Footer: navigation + social, then legal. No closing CTA here, the
          "Talk to my digital twin" button sits directly above it. */}
      <footer className="site-footer">
        <nav className="footer-nav" aria-label={dict.footer.nav}>
          <a href="#experience">{dict.nav.experience}</a>
          <a href="#education">{dict.nav.education}</a>
          <a href="#projects">{dict.nav.projects}</a>
          <a href="#certifications">{dict.nav.certifications}</a>
        </nav>

        <div className="footer-socials">
          <a href="mailto:msalmansaeedch786@gmail.com" aria-label={dict.common.email}><Mail size={20} /></a>
          <a href="https://github.com/msalmansaeedch" target="_blank" rel="noreferrer" aria-label="GitHub"><FiGithub size={20} /></a>
          <a href="https://linkedin.com/in/msalmansaeedch" target="_blank" rel="noreferrer" aria-label="LinkedIn"><FiLinkedin size={20} /></a>
          <a href="https://www.youtube.com/@msalmansaeedch" target="_blank" rel="noreferrer" aria-label="YouTube"><FiYoutube size={20} /></a>
        </div>

        <div className="footer-legal">
          <span>© {new Date().getFullYear()} Muhammad Salman · {dict.hero.location}</span>
          <span>Next.js · AWS Bedrock · Terraform</span>
        </div>
      </footer>
    </>
  );
}
