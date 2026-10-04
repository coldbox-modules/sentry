import { installClientPrivacy } from './clientPrivacy';
import { init, getClient, browserTracingIntegration, startBrowserTracingNavigationSpan, type BrowserClient, type BrowserOptions, type Event } from '@sentry/browser';
export { createFeedbackController } from './controller';
export { configureCapturePolicy } from './feedbackPrivacy';
export { mountFeedbackWidget } from './widget';
export async function percentageEligible(key: string, opaqueId: string, percentage: number) {
  if (!opaqueId || percentage <= 0) return false; if (percentage >= 100) return true;
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${key}:${opaqueId.toLowerCase()}`)));
  const bucket = new DataView(digest.buffer).getUint32(0) % 100 + 1;
  return bucket <= percentage;
}
export function stablePageName(name: string) { return name.split(/[?#]/)[0].replace(/\/(?:login|password|tokens?|invites?|kiosk|reset)(?:\/[^\s]*)?/gi, '/[private-page]').replace(/\/[A-Za-z0-9_-]{24,}(?=\/|$)/g, '/:id').replace(/\b[0-9a-f]{8}-[0-9a-f-]{27,}\b/gi, ':id').replace(/\/\d+(?=\/|$)/g, '/:id').slice(0, 256); }
export function sanitizeTransaction(event: Event) {
  event.transaction = stablePageName(event.transaction ?? 'document');
  delete event.request; delete event.extra; delete event.breadcrumbs;
  if (event.user) event.user = event.user.id ? { id: event.user.id } : undefined;
  for (const span of event.spans ?? []) { if (span.op?.startsWith('ui.')) span.description = 'interaction'; else if (span.description) span.description = stablePageName(span.description).replace(/https?:\/\/[^/\s]+[^\s]*/g, value => { try { const u = new URL(value); return u.origin; } catch { return '[resource]'; } });
    const data: Record<string, unknown> = {}; for (const [key, value] of Object.entries(span.data ?? {})) { if (/^(?:http\.request\.method|http\.response\.status_code|server\.address|browser\.|sentry\.|type$|op$)/.test(key) && ['string', 'number', 'boolean'].includes(typeof value)) data[key] = typeof value === 'string' ? value.split(/[?#]/)[0] : value; } span.data = data; }
  return event;
}
export function initializeBrowser(config: BrowserOptions & { enabled?: boolean; localVerification?: boolean; inertia?: boolean }, client?: BrowserClient) {
  if (client) { installClientPrivacy(client); return client; }
  const existing = getClient(); if (existing) { installClientPrivacy(existing); return existing; }
  const local = /^(?:localhost|127\.|0\.0\.0\.0|\[?::1\]?$)|\.(?:localhost|test)$/.test(window.location.hostname);
  if (!config.enabled || (local && !config.localVerification)) return undefined;
  init({ ...config, sendDefaultPii: false, replaysSessionSampleRate: 0, replaysOnErrorSampleRate: 0,
    integrations: [browserTracingIntegration({ instrumentNavigation: !config.inertia, beforeStartSpan: options => ({ ...options, name: stablePageName(options.name) }) })], beforeSendTransaction: sanitizeTransaction });
  const initialized = getClient(); if (initialized) installClientPrivacy(initialized); return initialized;
}
export function startInertiaNavigation(component: string) { const client = getClient(); if (client) return startBrowserTracingNavigationSpan(client, { name: stablePageName(component), op: 'navigation', attributes: { 'sentry.source': 'component' } }); }
