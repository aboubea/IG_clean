import { config } from "../config.js";
import type { Network } from "../networks.js";
import { demoConnector } from "./demo.js";
import type { Connector } from "./types.js";

/**
 * Connecteur à utiliser pour un réseau. Les connecteurs officiels (Meta, TikTok, LinkedIn) arrivent en
 * phase 2, une fois les apps développeur validées : ils s'enregistrent ici sans changer le reste du serveur.
 */
const official: Partial<Record<Network, Connector>> = {};

export function connectorFor(network: Network): Connector | null {
  return official[network] ?? (config.demoConnectors ? demoConnector(network) : null);
}

export function registerOfficialConnector(connector: Connector): void {
  official[connector.network] = connector;
}
