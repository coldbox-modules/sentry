import { expect, it, vi } from 'vitest';
import { initializeBrowser, sanitizeSpan, sanitizeTransaction, stablePageName, percentageEligible } from '../src/index';
vi.mock('@sentry/browser', () => ({ init: vi.fn(), getClient: () => undefined, browserTracingIntegration: () => ({}), startBrowserTracingNavigationSpan: vi.fn(), captureFeedback: vi.fn() }));
it('keeps stable navigation identities and strips URL credentials from spans', () => { expect(stablePageName('/people/123?token=private')).toBe('/people/:id'); const event = sanitizeTransaction({ transaction: '/people/123?token=private', spans: [{ description: 'GET https://user:password@api.test/private?token=secret', data: { 'http.request.method': 'GET', 'http.request.body': 'secret' } }] } as never); expect(JSON.stringify(event)).not.toContain('secret'); expect(JSON.stringify(event)).not.toContain('password'); });
it('honors explicit local verification and reuses a supplied client', () => { const supplied = { addEventProcessor: vi.fn(), getOptions: () => ({}) } as never; expect(initializeBrowser({ enabled: false, dsn: 'https://key@host/1' }, supplied)).toBe(supplied); expect(initializeBrowser({ enabled: false })).toBeUndefined(); });
it('uses stable percentage buckets matching the server SHA256 algorithm', async () => { const { webcrypto } = await import('node:crypto'); vi.stubGlobal('crypto', webcrypto); expect(await percentageEligible('feedback', 'USER', 50)).toBe(await percentageEligible('feedback', 'user', 50)); expect(await percentageEligible('feedback', '', 100)).toBe(false); expect(await percentageEligible('feedback', 'user', 100)).toBe(true); vi.unstubAllGlobals(); });

it('sanitizes standalone UI/resource spans and composes supplied-client filters exactly once', () => {
 const options = { beforeSendSpan: vi.fn(span => ({ ...span, data: { ...span.data, 'sentry.secret': 'PRIVATE' } })) };
 const previous = options.beforeSendSpan;
 const client = { addEventProcessor: vi.fn(), getOptions: () => options } as never;
 initializeBrowser({ enabled: false }, client); initializeBrowser({ enabled: false }, client);
 const result = options.beforeSendSpan({ op: 'ui.interaction.click', description: 'button#PRIVATE[email=PRIVATE]', data: { 'http.request.body': 'PRIVATE', 'browser.script': 'PRIVATE', 'sentry.origin': 'auto.ui.browser', 'server.address': 'https://user:PRIVATE@host.test/?token=PRIVATE' } } as never);
 expect(JSON.stringify(result)).not.toContain('PRIVATE'); expect(result.description).toBe('interaction');
 expect(previous).toHaveBeenCalledOnce();
 expect(result.data['sentry.origin']).toBe('auto.ui.browser');
 const resource = sanitizeSpan({ op: 'resource.script', description: 'https://user:PRIVATE@host.test/private?token=PRIVATE', data: {} } as never);
 expect(resource.description).toBe('https://host.test');
});

it('retains numeric standalone Web Vitals while excluding element and URL attributes', () => {
 const result = sanitizeSpan({ op: 'ui.webvital.lcp', description: '#PRIVATE', data: { 'browser.web_vital.lcp.value': 68, 'browser.web_vital.lcp.render_time': 60, 'browser.web_vital.lcp.element': '#PRIVATE', 'browser.web_vital.lcp.url': 'https://host/private?token=PRIVATE', 'sentry.op': 'ui.webvital.lcp', 'sentry.pageload.span_id': '0123456789abcdef', 'user_agent.original': navigator.userAgent }, measurements: { lcp: { value: 68, unit: 'millisecond' } } } as never);
 expect(JSON.stringify(result)).not.toContain('PRIVATE');
 expect(result.data['browser.web_vital.lcp.value']).toBe(68);
 expect(result.data['sentry.op']).toBe('ui.webvital.lcp');
 expect(result.measurements?.lcp.value).toBe(68);
 expect(result.data['user_agent.original']).toBe(navigator.userAgent);
});
