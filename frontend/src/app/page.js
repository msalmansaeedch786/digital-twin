import { redirect } from "next/navigation";
import { DEFAULT_LOCALE } from "./dictionaries/locales";

// Every real page lives under /[lang]. This keeps the bare domain working for
// the links already shared on LinkedIn and Instagram by sending it to the
// default locale.
//
// Amplify also has a 301 rule for this (see terraform/amplify.tf) so the
// redirect happens at the edge for most visitors; this is the in-app fallback
// and what makes `next dev` behave the same locally.
export default function RootPage() {
  redirect(`/${DEFAULT_LOCALE}`);
}
