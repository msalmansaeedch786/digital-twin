import "./globals.css";

export const metadata = {
  metadataBase: new URL("https://digital-twin-ivory.vercel.app"),
  title: "Salman | Senior Infrastructure Engineer",
  description:
    "Portfolio of Muhammad Salman — 6x AWS Certified Senior Infrastructure Consultant. Talk to his AI Digital Twin.",
  openGraph: {
    title: "Muhammad Salman — Senior Infrastructure Consultant",
    description:
      "6x AWS Certified professional specializing in Platform Engineering & Cloud Native. Chat with my AI Digital Twin.",
    url: "https://salman.dev",
    images: [{ url: "/salman-avatar.jpg", width: 800, height: 800 }],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Muhammad Salman — Senior Infrastructure Consultant",
    description:
      "6x AWS Certified. Talk to my AI Digital Twin.",
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body suppressHydrationWarning>{children}</body>
    </html>
  );
}
