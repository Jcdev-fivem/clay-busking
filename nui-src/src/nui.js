export const inGame = typeof window !== 'undefined' && typeof window.GetParentResourceName === 'function';
export const isPreview = import.meta.env.DEV && !inGame;

export async function nui(action, data = {}) {
  if (!inGame) return { ok: true };
  try {
    const response = await fetch('https://' + window.GetParentResourceName() + '/' + action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}
