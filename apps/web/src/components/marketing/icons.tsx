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

/**
 * The Notch Metrics mark, as a path rather than an `<img>`.
 *
 * Inline so it takes `currentColor`: the same mark is amber on the chip's
 * die and white in the headline, and the file in `public/logo.svg` is a
 * fixed colour. The path is copied from that file, so a redraw has to be
 * copied here too.
 */
export function NotchMark({ className }: Props) {
  return (
    <svg viewBox="0 0 512 512" fill="currentColor" className={className} aria-hidden>
      <path d="M451.279 149C459.024 149 466.451 152.076 471.927 157.553C477.404 163.029 480.48 170.457 480.48 178.201V275.538C480.48 283.283 477.404 290.71 471.927 296.187C466.451 301.663 459.024 304.739 451.279 304.739C443.534 304.739 436.107 301.663 430.631 296.187C425.154 290.71 422.078 283.283 422.078 275.538V248.712L343.702 327.049C330.925 339.816 313.602 346.988 295.54 346.988C277.477 346.988 260.153 339.816 247.377 327.049L185.626 265.298C184.722 264.392 183.648 263.672 182.465 263.182C181.283 262.691 180.015 262.439 178.735 262.438C177.455 262.438 176.186 262.691 175.004 263.182C173.821 263.672 172.747 264.392 171.843 265.298L82.5651 354.576C79.8919 357.445 76.6683 359.746 73.0866 361.342C69.5046 362.938 65.6373 363.796 61.7164 363.865C57.7957 363.934 53.9012 363.214 50.2653 361.745C46.6293 360.276 43.3262 358.09 40.5534 355.317C37.7805 352.545 35.5943 349.241 34.1256 345.605C32.657 341.97 31.9354 338.075 32.0045 334.154C32.0737 330.233 32.932 326.366 34.528 322.784C36.124 319.202 38.4256 315.978 41.2946 313.305L130.572 224.027C143.349 211.26 160.673 204.088 178.735 204.088C196.797 204.088 214.121 211.26 226.897 224.027L288.648 285.778C289.552 286.685 290.627 287.404 291.809 287.895C292.992 288.385 294.26 288.638 295.54 288.638C296.82 288.638 298.088 288.385 299.27 287.895C300.453 287.404 301.527 286.685 302.431 285.778L380.807 207.402H353.942C337.823 207.402 324.741 194.32 324.741 178.201C324.741 170.457 327.817 163.029 333.294 157.553C338.77 152.076 346.197 149 353.942 149H451.279Z" />
    </svg>
  );
}
