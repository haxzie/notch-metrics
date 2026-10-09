import { redirect } from "next/navigation";

/**
 * Pricing lives on the home page now. This keeps every old link, the
 * login's `next=/pricing` return, and anything a search engine indexed,
 * landing on the right section.
 */
export default function Pricing() {
  redirect("/#pricing");
}
