"use client";

import { useEffect, useRef, useState } from "react";

/**
 * The button that hands a ready prompt to whatever model somebody is using.
 *
 * The prompt is passed in rather than built here: it names the canonical URL
 * of the bundle, which only the server knows, and a client component that
 * guessed at the origin would copy a localhost link on a preview deploy.
 *
 * `navigator.clipboard` is unavailable on an insecure origin and can be
 * refused by permissions policy, so the failure path is a real path and not
 * a theoretical one. It falls back to selecting the text so a reader can copy
 * it by hand, which is worse than a click and much better than a button that
 * does nothing.
 */
export function CopyPrompt({ prompt, href }: { prompt: string; href: string }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  const textRef = useRef<HTMLTextAreaElement>(null);

  // Back to "Copy prompt" after a moment. Cleared on unmount, because a timer
  // that fires into an unmounted component is a React warning in dev and a
  // leak everywhere.
  useEffect(() => {
    if (state === "idle") return;
    const timer = setTimeout(() => setState("idle"), 2400);
    return () => clearTimeout(timer);
  }, [state]);

  async function copy() {
    try {
      await navigator.clipboard.writeText(prompt);
      setState("copied");
    } catch {
      setState("failed");
      const field = textRef.current;
      if (field) {
        field.focus();
        field.select();
      }
    }
  }

  return (
    <div className="panel p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-[16px] font-semibold tracking-tight">Start with your assistant</h2>
          <p className="text-ink/60 mt-1.5 max-w-md text-pretty text-[14px] leading-relaxed">
            Copy this prompt into Claude, ChatGPT or your editor. It points at a single file holding
            the manifest schema, the runtime contract and a worked example.
          </p>
        </div>

        <button
          type="button"
          onClick={copy}
          aria-label="Copy the prompt for building a custom app"
          className="bg-ink hover:bg-ink-soft focus-visible:outline-ink/40 shrink-0 rounded-full px-4 py-2 text-[13px] font-semibold text-white transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          {state === "copied" ? "Copied" : state === "failed" ? "Select it below" : "Copy prompt"}
        </button>
      </div>

      {/*
        Readable as well as copyable. Somebody deciding whether to paste this
        into a model wants to see what it says first, and a hidden buffer
        would also give the clipboard fallback nothing to select.
      */}
      <textarea
        ref={textRef}
        readOnly
        value={prompt}
        rows={6}
        spellCheck={false}
        aria-label="The prompt"
        className="border-ink/[0.08] bg-ink/[0.03] text-ink/75 focus-visible:outline-ink/20 mt-4 w-full resize-y rounded-xl border p-3.5 font-mono text-[12px] leading-relaxed focus-visible:outline focus-visible:outline-1"
      />

      <p className="text-ink/50 mt-3 text-[12.5px]">
        Reading it yourself?{" "}
        <a href={href} className="text-ink/70 hover:text-ink underline underline-offset-4">
          The same file in full
        </a>
        .
      </p>

      <span aria-live="polite" className="sr-only">
        {state === "copied" ? "Prompt copied to the clipboard" : ""}
      </span>
    </div>
  );
}
