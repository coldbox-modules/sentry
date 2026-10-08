// Script-tag entry keeps replay/screenshot dependencies in lazy ES-module chunks.
const base = new URL('./esm/index.js', (document.currentScript as HTMLScriptElement).src).href;
let loading: Promise<typeof import('./index')> | undefined;
const ready = () => loading ??= import(/* @vite-ignore */ base);
Object.assign(window, { SentryBox: { ready, initializeBrowser: async (...args: Parameters<typeof import('./index').initializeBrowser>) => (await ready()).initializeBrowser(...args), mountFeedbackWidget: async (...args: Parameters<typeof import('./index').mountFeedbackWidget>) => (await ready()).mountFeedbackWidget(...args) } });
