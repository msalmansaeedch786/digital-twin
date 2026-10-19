import { getDictionary, isLocale, DEFAULT_LOCALE } from "../dictionaries";
import PortfolioClient from "./portfolio-client";
import LangHint from "../lang-hint";
import { yearsOfExperience } from "../career";

// Thin server component: it resolves the locale and hands the right dictionary
// to the client component. The portfolio itself needs hooks (theme toggle,
// typewriter), so it stays "use client" and cannot await params itself.
export default async function Page({ params }) {
  const { lang } = await params;
  const locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  return (
    <>
      {/* Computed at build time so the prerendered HTML is already right; the
          client recomputes after mount in case the site has not been rebuilt
          since the last anniversary of CAREER_START. */}
      <PortfolioClient lang={locale} dict={getDictionary(locale)} experienceYears={yearsOfExperience()} />
      {/* Only on the portfolio: this is where the edge 301 lands everyone, so
          it is where a German visitor needs the nudge. The chat page has a
          fixed input bar at the bottom that this would sit on top of, and by
          then the reader has already picked a language anyway. */}
      <LangHint lang={locale} />
    </>
  );
}
