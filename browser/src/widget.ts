import { createFeedbackController } from './controller';
import { cornerPoint, constrain, keyCorner, nearestCorner, readCorner, saveCorner, type Bounds, type Point } from './feedbackPosition';
import { configureCapturePolicy, type CapturePolicy } from './feedbackPrivacy';
const defaults = { title: 'Feedback', open: 'Send feedback', close: 'Close', message: 'What happened?', submit: 'Send', done: 'Done', remove: 'Remove screenshot', success: 'Thank you. Your feedback was accepted.', sendFailed: 'Feedback could not be sent. Please try again.', messageRequired: 'Enter a message.', unavailable: 'Feedback is unavailable.', disclosure: 'Opening feedback uploads the recent replay buffer. Your message and screenshot are sent only when you submit.', pending: 'Preparing capture…', ready: 'Review your screenshot', removed: 'Screenshot removed', private: 'Text feedback only on this page', captureUnavailable: 'Capture unavailable; you can still send text feedback.', moved: 'Feedback button moved' };
export function mountFeedbackWidget(options: { eligible?: () => boolean; labels?: Partial<typeof defaults>; policy?: CapturePolicy; component?: () => string; className?: string } = {}) {
  let enabled = options.eligible?.() ?? true;
  configureCapturePolicy(options.policy ?? {});
  const labels = { ...defaults, ...options.labels }; const abort = new AbortController();
  const root = document.createElement('div'); root.dataset.feedbackUi = ''; root.dataset.sentryBlock = ''; root.className = options.className ?? '';
  root.innerHTML = `<style>
.sentry-feedback-trigger{position:fixed;left:0;top:0;z-index:2147483000;width:48px;height:48px;border-radius:50%;background:#1b4252cc;color:white;border:2px solid #fff8;box-shadow:0 4px 18px #0003;touch-action:none;font:24px system-ui;cursor:pointer}.sentry-feedback-dialog{border:1px solid #ccc;border-radius:16px;padding:24px;max-width:480px;width:calc(100vw - 48px);font:16px/1.5 system-ui;color:#172d38;background:#fff}.sentry-feedback-dialog::backdrop{background:#12222d88}.sentry-feedback-dialog textarea{box-sizing:border-box;width:100%;font:inherit;min-height:100px}.sentry-feedback-dialog button{font:inherit;margin:8px 8px 0 0;padding:8px 14px}.sentry-feedback-dialog img{max-width:100%;max-height:220px}.sentry-feedback-probe{position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)}.sentry-feedback-sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}
</style><div class="sentry-feedback-probe"></div><button class="sentry-feedback-trigger" type="button">✎</button><span class="sentry-feedback-sr" role="status"></span><dialog class="sentry-feedback-dialog"><h2></h2><p class="disclosure"></p><form><label><span></span><textarea required maxlength="4000"></textarea></label><p class="capture" role="status"></p><img hidden alt=""><button class="remove" type="button"></button><p class="error" role="alert"></p><button class="submit" type="submit"></button></form><p class="success" role="status" hidden></p><button class="close" type="button"></button></dialog>`;
  root.hidden = !enabled;
  document.body.append(root);
  const select = <T extends Element>(selector: string) => root.querySelector<T>(selector)!;
  const trigger = select<HTMLButtonElement>('.sentry-feedback-trigger'), dialog = select<HTMLDialogElement>('dialog'), message = select<HTMLTextAreaElement>('textarea'), image = select<HTMLImageElement>('img');
  const title = select<HTMLHeadingElement>('h2'); title.id = `sentry-feedback-${crypto.randomUUID()}`; title.textContent = labels.title; dialog.setAttribute('aria-labelledby', title.id);
  trigger.setAttribute('aria-label', labels.open); trigger.title = labels.open;
  select('.disclosure').textContent = labels.disclosure; select('label span').textContent = labels.message;
  select('.submit').textContent = labels.submit; select('.remove').textContent = labels.remove; select('.close').textContent = labels.close; select('.success').textContent = labels.success;
  const controller = createFeedbackController({ eligible: () => enabled && (options.eligible?.() ?? true), component: options.component,
    changed(state) { message.value = state.message; message.disabled = state.busy; select<HTMLButtonElement>('.submit').disabled = state.busy || state.capturing; select<HTMLButtonElement>('.close').disabled = state.busy;
      select('.error').textContent = state.error ? labels[state.error] : ''; select('.capture').textContent = state.captureState === 'unavailable' ? labels.captureUnavailable : labels[state.captureState];
      image.hidden = !state.screenshot; if (state.screenshot) image.src = state.screenshot.previewUrl; else image.removeAttribute('src'); select<HTMLButtonElement>('.remove').hidden = !state.screenshot;
      select<HTMLFormElement>('form').hidden = state.success; select<HTMLElement>('.success').hidden = !state.success;
      if (state.success) { select('.close').textContent = labels.done; select<HTMLButtonElement>('.close').focus(); }
    } });
  const listen = (target: EventTarget, name: string, fn: EventListener) => target.addEventListener(name, fn, { signal: abort.signal });
  listen(trigger, 'click', () => { if (suppressClick) { suppressClick = false; return; } if (dialog.open) return; void controller.open(); dialog.showModal(); message.focus(); });
  const close = () => { if (controller.state.busy) return; controller.close(); dialog.close(); trigger.focus(); };
  listen(select('.close'), 'click', close); listen(dialog, 'cancel', event => { event.preventDefault(); close(); });
  listen(select('form'), 'submit', event => { event.preventDefault(); void controller.submit(); }); listen(message, 'input', () => controller.setMessage(message.value)); listen(select('.remove'), 'click', controller.removeScreenshot);
  const cancelNavigation = () => { controller.cancel(); dialog.close(); };
  listen(window, 'popstate', cancelNavigation); listen(window, 'hashchange', cancelNavigation);
  let corner = readCorner(), position: Point | undefined, frame = 0, suppressClick = false;
  let pointer: { id: number; start: Point; origin: Point; moved: boolean } | undefined;
  const media = window.matchMedia('(prefers-reduced-motion: reduce)');
  function bounds(): Bounds { const css = getComputedStyle(select('.sentry-feedback-probe')); const number = (s: string) => parseFloat(s) || 0; const v = window.visualViewport; const left = (v?.offsetLeft ?? 0) + 16 + number(css.paddingLeft), top = (v?.offsetTop ?? 0) + 16 + number(css.paddingTop); return { left, top, right: Math.max(left, (v?.offsetLeft ?? 0) + (v?.width ?? innerWidth) - 64 - number(css.paddingRight)), bottom: Math.max(top, (v?.offsetTop ?? 0) + (v?.height ?? innerHeight) - 64 - number(css.paddingBottom)) }; }
  function place(value: Point) { position = value; trigger.style.transform = `translate3d(${value.x}px,${value.y}px,0)`; }
  function settle(animate = true) { cancelAnimationFrame(frame); const target = cornerPoint(corner, bounds()), start = position ?? target; if (!animate || media.matches) { place(target); return; } const began = performance.now(); const tick = (now: number) => { const elapsed = (now - began) / 700, progress = 1 - Math.exp(-6 * elapsed) * Math.cos(7.5 * elapsed); place(constrain({ x: start.x + (target.x - start.x) * progress, y: start.y + (target.y - start.y) * progress }, bounds())); if (elapsed < 1) frame = requestAnimationFrame(tick); else place(target); }; frame = requestAnimationFrame(tick); }
  function choose(next: typeof corner) { corner = next; saveCorner(corner); select('[role="status"]').textContent = labels.moved; settle(); }
  listen(trigger, 'pointerdown', raw => { const event = raw as PointerEvent; if (!event.isPrimary || event.button !== 0 || pointer) return; cancelAnimationFrame(frame); pointer = { id: event.pointerId, start: { x: event.clientX, y: event.clientY }, origin: position ?? cornerPoint(corner, bounds()), moved: false }; suppressClick = false; trigger.setPointerCapture(event.pointerId); });
  listen(trigger, 'pointermove', raw => { const event = raw as PointerEvent; if (!pointer || pointer.id !== event.pointerId) return; const dx = event.clientX - pointer.start.x, dy = event.clientY - pointer.start.y; if (!pointer.moved && Math.hypot(dx, dy) < 8) return; pointer.moved = true; place(constrain({ x: pointer.origin.x + dx, y: pointer.origin.y + dy }, bounds())); });
  const end = (raw: Event) => { const event = raw as PointerEvent; if (!pointer || pointer.id !== event.pointerId) return; suppressClick = pointer.moved || event.type === 'pointercancel'; pointer = undefined; if (trigger.hasPointerCapture(event.pointerId)) trigger.releasePointerCapture(event.pointerId); if (suppressClick) choose(nearestCorner(position!, bounds())); else settle(); };
  listen(trigger, 'pointerup', end); listen(trigger, 'pointercancel', end); listen(trigger, 'lostpointercapture', end);
  listen(trigger, 'keydown', raw => { const event = raw as KeyboardEvent; const next = keyCorner(corner, event.key); if (next) { event.preventDefault(); choose(next); } });
  listen(window, 'resize', () => settle(false)); if (window.visualViewport) { listen(window.visualViewport, 'resize', () => settle(false)); listen(window.visualViewport, 'scroll', () => settle(false)); } listen(media, 'change', () => settle(false)); settle(false);
  if (enabled) void import('./feedbackReplay').then(m => { if (enabled) m.setFeedbackReplayEnabled(true); });
  return { controller, setEnabled(value: boolean) { enabled = value; if (!value) { cancelNavigation(); root.hidden = true; } else root.hidden = false; void import('./feedbackReplay').then(m => m.setFeedbackReplayEnabled(value)); }, dispose() { enabled = false; abort.abort(); cancelAnimationFrame(frame); controller.cancel(); root.remove(); void import('./feedbackReplay').then(m => m.setFeedbackReplayEnabled(false)); } };
}
