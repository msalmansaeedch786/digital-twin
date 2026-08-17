import "../globals.css";
import { getDictionary, LOCALES, isLocale } from "../dictionaries";

const SITE = "https://msalmansaeedch.de";

// Prerenders /en and /de at build time, so both locales stay static files on
// Amplify rather than becoming on-demand renders.
export function generateStaticParams() {
  return LOCALES.map((lang) => ({ lang }));
}

// Without this, [lang] matches ANY first segment: /avatar, /foo and every typo
// would render the portfolio with lang="avatar" instead of 404ing, giving
// search engines unlimited duplicate pages. Restrict the segment to the params
// generated above.
export const dynamicParams = false;

export async function generateMetadata({ params }) {
  const { lang } = await params;
  const locale = isLocale(lang) ? lang : "en";
  const t = getDictionary(locale).meta;

  return {
    metadataBase: new URL(SITE),
    title: t.title,
    description: t.description,
    alternates: {
      canonical: `${SITE}/${locale}`,
      // hreflang: this is what lets Google serve the German page to German
      // searchers instead of treating it as a duplicate of the English one.
      languages: {
        en: `${SITE}/en`,
        de: `${SITE}/de`,
        "x-default": `${SITE}/en`,
      },
    },
    openGraph: {
      title: t.ogTitle,
      description: t.ogDescription,
      url: `${SITE}/${locale}`,
      siteName: "Muhammad Salman | AI Digital Twin",
      locale: locale === "de" ? "de_DE" : "en_US",
      images: [
        {
          url: "/twin-cover.png",
          width: 1200,
          height: 630,
          alt: t.ogTitle,
        },
      ],
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: t.ogTitle,
      description: t.twitterDescription,
      images: ["/twin-cover.png"],
    },
  };
}

// This is the root layout: every route lives under [lang], so there is no
// app/layout.js above it.
export default async function RootLayout({ children, params }) {
  const { lang } = await params;
  return (
    <html lang={isLocale(lang) ? lang : "en"}>
      <body suppressHydrationWarning>{children}</body>
    </html>
  );
}
