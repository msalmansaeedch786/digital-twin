import { getDictionary, isLocale, DEFAULT_LOCALE } from "../dictionaries";
import PortfolioClient from "./portfolio-client";

// Thin server component: it resolves the locale and hands the right dictionary
// to the client component. The portfolio itself needs hooks (theme toggle,
// typewriter), so it stays "use client" and cannot await params itself.
export default async function Page({ params }) {
  const { lang } = await params;
  const locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  return <PortfolioClient lang={locale} dict={getDictionary(locale)} />;
}
