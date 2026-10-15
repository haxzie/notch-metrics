import Link from "next/link";
import { AppleMark } from "./icons";

export function DownloadButton({
  size = "md",
  className = "",
}: {
  size?: "md" | "lg";
  className?: string;
}) {
  return (
    <Link
      href="/download"
      className={`bg-ink hover:bg-ink/85 inline-flex items-center gap-2 rounded-full font-semibold text-white shadow-[0_10px_30px_-10px_rgba(11,10,14,0.5)] transition ${
        size === "lg" ? "h-12 px-6 text-[15px]" : "h-10 px-5 text-sm"
      } ${className}`}
    >
      <AppleMark className={size === "lg" ? "h-4 w-4" : "h-3.5 w-3.5"} />
      Download for Mac
    </Link>
  );
}
