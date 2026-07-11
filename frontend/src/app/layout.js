import "./globals.css";

export const metadata = {
  metadataBase: new URL("https://main.dtogabptwtao.amplifyapp.com"),
  title: "Salman | Senior Infrastructure Engineer",
  description:
    "Portfolio of Muhammad Salman, 6x AWS Certified Senior Infrastructure Consultant. Talk to his AI Digital Twin.",
  openGraph: {
    title: "AI Digital Twin: Serverless RAG Chatbot on AWS",
    description:
      "Chat with my AI digital twin and ask about my cloud, DevOps, and platform engineering experience. Built serverless on AWS.",
    url: "https://main.dtogabptwtao.amplifyapp.com",
    siteName: "Muhammad Salman | AI Digital Twin",
    images: [
      {
        url: "/twin-cover.png",
        width: 1200,
        height: 630,
        alt: "AI Digital Twin: Serverless RAG Chatbot on AWS",
      },
    ],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "AI Digital Twin: Serverless RAG Chatbot on AWS",
    description:
      "Chat with my AI digital twin, built serverless on AWS.",
    images: ["/twin-cover.png"],
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body suppressHydrationWarning>{children}</body>
    </html>
  );
}
