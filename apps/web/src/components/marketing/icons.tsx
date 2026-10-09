/**
 * The handful of glyphs the marketing pages need, inlined so the pages ship
 * no icon font. Stroke icons share one frame so they sit on the same tiles.
 */

type Props = { className?: string };

function Stroke({ className, children }: Props & { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
    >
      {children}
    </svg>
  );
}

export function AppleMark({ className }: Props) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className} aria-hidden>
      <path d="M16.37 12.76c-.03-2.6 2.12-3.85 2.22-3.91-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.16-3.12.94-3.93.94-.81 0-2.06-.92-3.39-.89-1.74.03-3.35 1.01-4.25 2.58-1.81 3.14-.46 7.8 1.3 10.35.86 1.25 1.89 2.65 3.24 2.6 1.3-.05 1.79-.84 3.36-.84 1.57 0 2.01.84 3.39.81 1.4-.02 2.28-1.27 3.14-2.52.99-1.45 1.4-2.85 1.42-2.92-.03-.01-2.72-1.04-2.74-4.16ZM13.78 5.12c.72-.87 1.2-2.08 1.07-3.29-1.03.04-2.29.69-3.03 1.56-.66.77-1.25 2-1.09 3.18 1.15.09 2.33-.58 3.05-1.45Z" />
    </svg>
  );
}

export function NotchIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <rect x="2.5" y="4" width="19" height="14" rx="2.5" />
      <path d="M8.5 4v1.5a1.5 1.5 0 0 0 1.5 1.5h4a1.5 1.5 0 0 0 1.5-1.5V4" />
      <path d="M9 21h6" />
    </Stroke>
  );
}

export function CursorIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M5 3.5 19 10.2l-6.1 1.9-2.6 5.9Z" />
    </Stroke>
  );
}

export function KeyIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <circle cx="8" cy="14" r="4.5" />
      <path d="M11.3 10.7 20 2M16 6l2.5 2.5M13.5 8.5 16 11" />
    </Stroke>
  );
}

export function LinkIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1" />
      <path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 1 0 5.66 5.66l1-1" />
    </Stroke>
  );
}

export function SparkIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1" />
    </Stroke>
  );
}

export function TerminalIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <rect x="3" y="4.5" width="18" height="15" rx="2.5" />
      <path d="m7.5 9.5 3 2.5-3 2.5M12.5 15h4" />
    </Stroke>
  );
}

export function GridIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
      <rect x="13.5" y="3.5" width="7" height="7" rx="1.5" />
      <rect x="3.5" y="13.5" width="7" height="7" rx="1.5" />
      <rect x="13.5" y="13.5" width="7" height="7" rx="1.5" />
    </Stroke>
  );
}

export function ListIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M8 6h12M8 12h12M8 18h12" />
      <circle cx="4" cy="6" r="0.9" fill="currentColor" />
      <circle cx="4" cy="12" r="0.9" fill="currentColor" />
      <circle cx="4" cy="18" r="0.9" fill="currentColor" />
    </Stroke>
  );
}

export function ChipIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <rect x="6" y="6" width="12" height="12" rx="2" />
      <rect x="9.5" y="9.5" width="5" height="5" rx="1" />
      <path d="M9 2.5v3.5M15 2.5v3.5M9 18v3.5M15 18v3.5M2.5 9h3.5M2.5 15h3.5M18 9h3.5M18 15h3.5" />
    </Stroke>
  );
}

export function ShieldIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M12 2.8 4.5 5.6v5.7c0 4.6 3.2 8.4 7.5 9.9 4.3-1.5 7.5-5.3 7.5-9.9V5.6Z" />
      <path d="m9 12 2 2 4-4" />
    </Stroke>
  );
}

export function RefreshIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M20 12a8 8 0 1 1-2.3-5.6" />
      <path d="M20 3.5V8h-4.5" />
    </Stroke>
  );
}

export function MoonIcon({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" />
    </Stroke>
  );
}

export function ArrowRight({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M5 12h14M13 6l6 6-6 6" />
    </Stroke>
  );
}

export function Check({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="m5 12.5 4.5 4.5L19 7.5" />
    </Stroke>
  );
}

export function Plus({ className }: Props) {
  return (
    <Stroke className={className}>
      <path d="M12 5v14M5 12h14" />
    </Stroke>
  );
}
