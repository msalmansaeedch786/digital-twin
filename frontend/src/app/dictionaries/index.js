import en from "./en.json";
import de from "./de.json";

export const LOCALES = ["en", "de"];
export const DEFAULT_LOCALE = "en";

const DICTIONARIES = { en, de };

export function isLocale(value) {
  return LOCALES.includes(value);
}

/**
 * Returns the dictionary for a locale, falling back to English.
 *
 * Imported statically rather than with a dynamic import() so both files are
 * resolved at build time: the pages are prerendered, and the whole payload is
 * only a few KB per language.
 */
export function getDictionary(locale) {
  return DICTIONARIES[locale] ?? DICTIONARIES[DEFAULT_LOCALE];
}

/** The other locale, for the language toggle. */
export function otherLocale(locale) {
  return locale === "de" ? "en" : "de";
}
