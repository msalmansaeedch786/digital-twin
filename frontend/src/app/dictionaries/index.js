import en from "./en.json";
import de from "./de.json";

// Re-exported so server components can keep importing everything from one
// place; client components must import from ./locales directly, or they pull
// both dictionaries into the browser bundle.
export { LOCALES, DEFAULT_LOCALE, isLocale, otherLocale } from "./locales";

import { DEFAULT_LOCALE } from "./locales";

const DICTIONARIES = { en, de };

/**
 * Returns the dictionary for a locale, falling back to English.
 *
 * Imported statically rather than with a dynamic import() so both files are
 * resolved at build time: the pages are prerendered, and only the locale
 * actually being rendered is serialised into that page's payload.
 */
export function getDictionary(locale) {
  return DICTIONARIES[locale] ?? DICTIONARIES[DEFAULT_LOCALE];
}
