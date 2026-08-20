"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { otherLocale } from "./dictionaries/locales";

// Written in the language being OFFERED, not the one being displayed: a German
// speaker on the English page has to be able to read the offer for it to work.
// Kept here rather than in the dictionaries so the full dictionary files stay
// server-side and out of the client bundle.
const STRINGS = {
  de: { text: "Diese Seite gibt es auch auf Deutsch.", cta: "Zu Deutsch", dismiss: "Schließen" },
  en: { text: "This page is also available in English.", cta: "Switch to English", dismiss: "Dismiss" },
};

const STORAGE_KEY = "lang-hint-dismissed";

/**
 * Offers the other locale when the visitor's browser is set to it.
 *
 * The bare domain 301s to /en at the edge for everyone (see
 * terraform/amplify.tf), which is what keeps both locales static and cheap —
 * so a German visitor lands on English. Rather than move that decision to a
 * dynamic redirect, this points them one click away and remembers the answer.
 *
 * Renders nothing on the server and nothing on the first client paint: it is
 * gated on navigator.language, so committing to a state before mount would
 * mean a hydration mismatch.
 */
export default function LangHint({ lang }) {
  const [show, setShow] = useState(false);
  const pathname = usePathname();
  const target = otherLocale(lang);

  useEffect(() => {
    try {
      if (localStorage.getItem(STORAGE_KEY)) return;
    } catch {
      // Safari private mode throws on localStorage; showing the hint is the
      // harmless failure, so fall through rather than bail.
    }
    // "de", "de-DE", "de-AT" should all match; "den" should not.
    const prefers = (navigator.languages?.length ? navigator.languages : [navigator.language])
      .some((l) => typeof l === "string" && l.toLowerCase().split("-")[0] === target);
    if (prefers) setShow(true);
  }, [target]);

  if (!show) return null;

  const t = STRINGS[target];
  const href = (pathname || `/${lang}`).replace(new RegExp(`^/${lang}(?=/|$)`), `/${target}`);

  const dismiss = () => {
    setShow(false);
    try {
      localStorage.setItem(STORAGE_KEY, "1");
    } catch {}
  };

  return (
    <div className="lang-hint" role="region" aria-label={t.text}>
      <span className="lang-hint-text">{t.text}</span>
      <Link href={href} className="lang-hint-cta" onClick={dismiss} lang={target}>
        {t.cta}
      </Link>
      <button type="button" className="lang-hint-close" onClick={dismiss} aria-label={t.dismiss}>
        ×
      </button>
    </div>
  );
}
