import "./globals.css";

export const metadata = {
  title: "Salman | Senior Infrastructure Engineer",
  description: "Portfolio of Muhammad Salman, powered by a Digital Twin AI.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>{children}</body>
    </html>
  );
}
