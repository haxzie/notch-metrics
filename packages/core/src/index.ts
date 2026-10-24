/**
 * Everything needed to write a local Notch Metrics connector.
 *
 * A connector is one app, its credential and every metric it offers. It runs
 * on the user's own Mac against their own API key and is never uploaded.
 *
 * Nothing here is required at run time: a connector exports two plain
 * functions and the runner supplies the context. This package exists so that
 * writing one in TypeScript is checked by the compiler rather than by
 * `register_connector` rejecting it afterwards.
 */
export * from "./connector.ts";
export * from "./runtime.ts";
