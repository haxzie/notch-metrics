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
      className={`inline-flex items-center gap-2 rounded-full bg-white font-semibold text-black shadow-[0_0_0_1px_rgba(255,255,255,0.4),0_10px_30px_-10px_rgba(255,255,255,0.45)] transition hover:bg-white/90 ${
        size === "lg" ? "h-12 px-6 text-[15px]" : "h-10 px-5 text-sm"
      } ${className}`}
    >
      <AppleMark className={size === "lg" ? "h-4 w-4" : "h-3.5 w-3.5"} />
      Download for Mac
    </Link>
  );
}
