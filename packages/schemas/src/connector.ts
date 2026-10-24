/**
 * The local-connector contract, owned by the published package.
 *
 * It used to be defined here. It moved to `@notchmetrics/core` because an
 * agent writing a connector needs these types in their editor, and a type
 * that only exists inside a private monorepo cannot be installed. Re-exported
 * rather than copied so there is still exactly one definition — the Worker,
 * the runner and the author all read the same file.
 *
 * `@notchmetrics/core` deliberately depends on nothing but zod, which is what
 * lets it be published at all.
 */
export {
  AppId as ConnectorAppId,
  AuthField as ConnectorAuthField,
  ConnectorId,
  LocalConnectorManifest,
  LocalListItem,
  LocalMetricDescriptor,
  LocalMetricId,
  LocalMetricOutcome,
  LocalMetricResult,
  LocalMetricShape,
  LocalVerifyResult,
} from "@notchmetrics/core";
export type {
  ConnectorContext,
  ConnectorModule,
  MetricRequest as ConnectorMetricRequest,
} from "@notchmetrics/core";
