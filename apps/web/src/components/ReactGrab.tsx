"use client";

import { useEffect } from "react";

/**
 * Loads react-grab in development only. Hover any element and press ⌘C to
 * copy it with its component stack and source location, ready to paste to
 * an agent.
 *
 * A dynamic import behind a NODE_ENV check rather than a plain import: Next
 * inlines NODE_ENV at build time, so the production bundle drops the import
 * entirely instead of shipping a devtool to every visitor.
 */
export function ReactGrab() {
  useEffect(() => {
    if (process.env.NODE_ENV === "development") {
      void import("react-grab");
    }
  }, []);
  return null;
}
