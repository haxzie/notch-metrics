import Link from "next/link";

/**
 * Next's built-in 404 ships its own dark styles, which was invisible while
 * the site was dark and is a black page in the middle of a light one now.
 */
export default function NotFound() {
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col items-center justify-center gap-4 px-6 text-center">
      <p className="eyebrow">404</p>
      <h1 className="text-3xl font-bold tracking-tight">This page is not here</h1>
      <p className="text-ink/55 text-[15px] leading-relaxed">
        The link is wrong, or the page has moved. Everything Notch Metrics shows is on the home
        page.
      </p>
      <Link
        href="/"
        className="bg-ink hover:bg-ink/85 mt-2 inline-flex h-11 items-center rounded-full px-5 text-sm font-semibold text-white transition"
      >
        Back to the home page
      </Link>
    </main>
  );
}
