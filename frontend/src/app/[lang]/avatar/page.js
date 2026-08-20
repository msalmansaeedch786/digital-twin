import { getDictionary, isLocale, DEFAULT_LOCALE } from "../../dictionaries";
import { SITE, localeAlternates } from "../../seo";
import AvatarClient from "./avatar-client";

// Without this the chat page inherits the layout's metadata, which points at
// the portfolio: /de/avatar declared canonical /de, told Google it was a
// duplicate of the portfolio, and took itself out of the index. Metadata is
// merged shallowly, so openGraph has to be restated in full rather than
// patched — a partial object would drop the image and site name.
export async function generateMetadata({ params }) {
  const { lang } = await params;
  const locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  const t = getDictionary(locale).meta;

  return {
    metadataBase: new URL(SITE),
    title: t.avatarTitle,
    description: t.avatarDescription,
    alternates: localeAlternates(locale, "/avatar"),
    openGraph: {
      title: t.avatarTitle,
      description: t.avatarDescription,
      url: `${SITE}/${locale}/avatar`,
      siteName: "Muhammad Salman | AI Digital Twin",
      locale: locale === "de" ? "de_DE" : "en_US",
      images: [
        {
          url: "/twin-cover.png",
          width: 1200,
          height: 630,
          alt: t.avatarTitle,
        },
      ],
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: t.avatarTitle,
      description: t.twitterDescription,
      images: ["/twin-cover.png"],
    },
  };
}

// Thin server component, same pattern as the portfolio page: resolve the
// locale here so the chat UI can stay a client component.
export default async function Page({ params }) {
  const { lang } = await params;
  const locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  return <AvatarClient lang={locale} dict={getDictionary(locale)} />;
}
