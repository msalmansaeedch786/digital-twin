// When my professional career started (NorthBay Solutions, July 2019).
//
// The years of experience shown on the portfolio are computed from this rather
// than typed into the dictionaries, because a typed "6+" went stale silently.
// The backend has the same date in CAREER_START in lambdas/api/main.py, which
// is what the twin quotes; change both together.
export const CAREER_START = { year: 2019, month: 7 };

/** Full years since CAREER_START, as of `now`. */
export function yearsOfExperience(now = new Date()) {
  const years = now.getFullYear() - CAREER_START.year;
  return now.getMonth() + 1 < CAREER_START.month ? years - 1 : years;
}
