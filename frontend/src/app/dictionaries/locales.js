// Locale primitives, deliberately free of any dictionary import.
//
// Client components need otherLocale/LOCALES for the language toggle. Taking
// them from ./index would pull en.json AND de.json into the client bundle —
// every visitor downloading both languages of the whole portfolio on top of
// the one already inlined in the RSC payload. Keeping these here means the
// dictionaries stay server-side.
export const LOCALES = ["en", "de"];
export const DEFAULT_LOCALE = "en";

export function isLocale(value) {
  return LOCALES.includes(value);
}

/** The other locale, for the language toggle. */
export function otherLocale(locale) {
  return locale === "de" ? "en" : "de";
}
