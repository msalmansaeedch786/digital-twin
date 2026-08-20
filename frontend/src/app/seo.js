import { LOCALES, DEFAULT_LOCALE } from "./dictionaries/locales";

export const SITE = "https://msalmansaeedch.de";

/**
 * Canonical + hreflang for one page in one locale.
 *
 * Every localised route needs this, and getting it wrong is invisible in the
 * browser but costly in search: a page that inherits the wrong canonical tells
 * Google it is a duplicate of another page and drops out of the index. Built in
 * one place so a new locale only has to be added to LOCALES.
 *
 * `path` is the part after the locale segment ("" for the portfolio,
 * "/avatar" for the chat), with a leading slash and no trailing one.
 */
export function localeAlternates(locale, path = "") {
  return {
    canonical: `${SITE}/${locale}${path}`,
    languages: {
      ...Object.fromEntries(
        LOCALES.map((l) => [l, `${SITE}/${l}${path}`])
      ),
      "x-default": `${SITE}/${DEFAULT_LOCALE}${path}`,
    },
  };
}
