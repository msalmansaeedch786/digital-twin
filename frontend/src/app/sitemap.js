import { LOCALES } from "./dictionaries/locales";
import { SITE, localeAlternates } from "./seo";

// The routes that exist in every locale, relative to the /[lang] prefix.
const PATHS = [
  { path: "", priority: 1 },
  { path: "/avatar", priority: 0.8 },
];

/**
 * Both locales are listed as first-class URLs, each carrying the full set of
 * hreflang alternates. Without them Google treats /en and /de as competing
 * duplicates and picks one; with them it knows they are the same page in two
 * languages and serves German searchers /de.
 *
 * The bare / and /avatar URLs are deliberately absent: they 301 to their /en
 * equivalents (see terraform/amplify.tf), and listing a redirect in a sitemap
 * is a Search Console warning.
 */
export default function sitemap() {
  const lastModified = new Date();

  return PATHS.flatMap(({ path, priority }) =>
    LOCALES.map((locale) => ({
      url: `${SITE}/${locale}${path}`,
      lastModified,
      changeFrequency: "monthly",
      priority,
      alternates: { languages: localeAlternates(locale, path).languages },
    }))
  );
}
