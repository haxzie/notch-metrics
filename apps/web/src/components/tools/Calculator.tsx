"use client";

import { useMemo, useState } from "react";
import { CURRENCIES, currencySymbol, formatUnit } from "@/lib/tools/format";
import { toolBySlug, type ToolField } from "@/lib/tools";

/**
 * The interactive half of a free tool page.
 *
 * Takes a slug rather than the tool itself: `compute` is a function, and a
 * function cannot cross the server-to-client boundary as a prop. The client
 * imports the registry and looks the tool up, which costs a small bundle and
 * keeps one definition of every calculator.
 *
 * Everything around this component is server-rendered prose. That split is
 * deliberate: a page whose content only exists after JavaScript runs has
 * nothing for a crawler to read.
 */

/** The canonical number for a field: minor units for money, as typed otherwise. */
function parse(field: ToolField, raw: string): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return 0;
  const value = field.unit === "money" ? Math.round(n * 100) : n;
  return field.min !== undefined && value < field.min ? field.min : value;
}

/** The default, as the string the input should start with. */
function initial(field: ToolField): string {
  return field.unit === "money" ? String(field.default / 100) : String(field.default);
}

export function Calculator({ slug }: { slug: string }) {
  const tool = toolBySlug(slug);

  const [raw, setRaw] = useState<Record<string, string>>(() =>
    Object.fromEntries((tool?.fields ?? []).map((field) => [field.key, initial(field)])),
  );
  const [currency, setCurrency] = useState<string>("USD");

  const results = useMemo(() => {
    if (!tool) return {};
    const values = new Map(
      tool.fields.map((field) => [field.key, parse(field, raw[field.key] ?? "")]),
    );
    // A missing key can only mean a field was renamed without its compute
    // following, which a build would not catch. Zero keeps the page usable.
    return tool.compute((key) => values.get(key) ?? 0);
  }, [tool, raw]);

  if (!tool) return null;

  const hasMoney =
    tool.fields.some((f) => f.unit === "money") || tool.outputs.some((o) => o.unit === "money");
  const symbol = currencySymbol(currency);
  const primary = tool.outputs.find((output) => output.primary) ?? tool.outputs[0];
  const secondary = tool.outputs.filter((output) => output !== primary);

  return (
    <section className="panel mt-10 overflow-hidden" aria-label={`${tool.name}`}>
      <div className="flex flex-col gap-6 p-6 sm:p-7">
        {hasMoney && (
          <div className="flex items-center justify-between gap-4">
            <span className="eyebrow">Currency</span>
            <select
              value={currency}
              onChange={(event) => setCurrency(event.target.value)}
              aria-label="Currency"
              className="rounded-lg border border-white/10 bg-white/[0.04] px-2.5 py-1.5 font-mono text-[12px] text-white/70 outline-none transition focus:border-white/25"
            >
              {CURRENCIES.map((code) => (
                <option key={code} value={code} className="bg-[#111013]">
                  {code}
                </option>
              ))}
            </select>
          </div>
        )}

        <div className="grid gap-5 sm:grid-cols-2">
          {tool.fields.map((field) => (
            <div key={field.key} className="flex flex-col gap-1.5">
              <label htmlFor={`${tool.slug}-${field.key}`} className="text-[14px] text-white/80">
                {field.label}
              </label>
              <div className="flex items-center rounded-xl border border-white/10 bg-white/[0.04] transition focus-within:border-white/25">
                {field.unit === "money" && (
                  <span className="pl-3 font-mono text-[13px] text-white/40">{symbol}</span>
                )}
                <input
                  id={`${tool.slug}-${field.key}`}
                  type="number"
                  inputMode="decimal"
                  value={raw[field.key] ?? ""}
                  min={
                    field.unit === "money" && field.min !== undefined ? field.min / 100 : field.min
                  }
                  step={field.step ?? (field.unit === "money" ? 0.01 : 1)}
                  onChange={(event) =>
                    setRaw((current) => ({ ...current, [field.key]: event.target.value }))
                  }
                  className="w-full bg-transparent px-3 py-2.5 font-mono text-[15px] text-white outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                />
                {field.unit === "percent" && (
                  <span className="pr-3 font-mono text-[13px] text-white/40">%</span>
                )}
              </div>
              {field.help && (
                <p className="text-[13px] leading-relaxed text-white/40">{field.help}</p>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* `aria-live` so a screen reader hears the answer change rather than
          only finding it if the user goes looking for it. */}
      <div aria-live="polite" className="border-t border-white/[0.07] bg-white/[0.02] p-6 sm:p-7">
        <p className="eyebrow">{primary?.label}</p>
        <p className="brand-text mt-1.5 text-4xl font-semibold tracking-tight sm:text-5xl">
          {formatUnit(results[primary?.key ?? ""] ?? null, primary?.unit ?? "count", currency)}
        </p>

        {secondary.length > 0 && (
          <dl className="mt-7 grid gap-x-8 gap-y-5 sm:grid-cols-2">
            {secondary.map((output) => (
              <div key={output.key}>
                <dt className="text-[13px] text-white/45">{output.label}</dt>
                <dd className="mt-1 font-mono text-[17px] text-white/90">
                  {formatUnit(results[output.key] ?? null, output.unit, currency)}
                </dd>
                {output.help && (
                  <dd className="mt-1 text-[12px] leading-relaxed text-white/35">{output.help}</dd>
                )}
              </div>
            ))}
          </dl>
        )}

        <p className="mt-7 border-t border-white/[0.06] pt-5 font-mono text-[12px] leading-relaxed text-white/35">
          {tool.formula}
        </p>
      </div>
    </section>
  );
}
