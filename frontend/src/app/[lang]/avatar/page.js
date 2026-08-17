import { getDictionary, isLocale, DEFAULT_LOCALE } from "../../dictionaries";
import AvatarClient from "./avatar-client";

// Thin server component, same pattern as the portfolio page: resolve the
// locale here so the chat UI can stay a client component.
export default async function Page({ params }) {
  const { lang } = await params;
  const locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  return <AvatarClient lang={locale} dict={getDictionary(locale)} />;
}
