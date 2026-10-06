/**
 * Lifts a brand colour that is too dark to show on this site's background.
 *
 * Brand colours are chosen against a white page. Dodo Payments' is `#111111`,
 * which on our near-black page renders a primary button that looks disabled.
 * Scaling toward white rather than shifting hue keeps what people actually
 * recognise about the colour.
 *
 * Mirrors `NotchTheme.tileFill` in the Mac app, including the floor.
 */
export function liftForDarkUI(hex: string): string {
  const value = Number.parseInt(hex.replace("#", ""), 16);
  if (Number.isNaN(value)) return "#6b7280";

  let r = (value >> 16) & 0xff;
  let g = (value >> 8) & 0xff;
  let b = value & 0xff;

  // Rec. 709 luma.
  const luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  if (luma >= 0.16) return hex;

  const lift = 0.28 / Math.max(luma, 0.04);
  r = Math.min(255, Math.round(r * lift) + 28);
  g = Math.min(255, Math.round(g * lift) + 28);
  b = Math.min(255, Math.round(b * lift) + 28);
  return `#${[r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("")}`;
}
