/**
 * Waits one paint, but never longer than `fallbackMs`.
 *
 * WebKit stops firing requestAnimationFrame for windows that are not visible,
 * which is exactly the situation during headless export and PDF rendering.
 * A bare `await new Promise(requestAnimationFrame)` hangs forever there.
 */
export function nextFrame(fallbackMs = 32) {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => { if (!done) { done = true; resolve(); } };
    requestAnimationFrame(finish);
    setTimeout(finish, fallbackMs);
  });
}
