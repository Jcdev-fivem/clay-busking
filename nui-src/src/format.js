export function formatMoney(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n) || n < 0) return '0';
  return Math.floor(n).toLocaleString('en-US');
}

export function digitsOnly(raw) {
  return String(raw ?? '').replace(/\D+/g, '');
}

export function quickTipAmounts(minTip = 1, maxTip = 100000) {
  return [100, 500, 1000, 5000].filter((n) => n >= minTip && n <= maxTip);
}

export function parseTipInput(raw, minTip = 1, maxTip = 100000) {
  const text = String(raw ?? '').trim();
  if (text.length === 0) {
    return { ok: false, error: 'กรุณาใส่จำนวนเงิน' };
  }
  if (!/^\d+$/.test(text)) {
    return { ok: false, error: 'กรุณากรอกเฉพาะตัวเลขจำนวนเต็ม' };
  }
  const value = Number(text);
  if (!Number.isSafeInteger(value) || value < minTip || value > maxTip) {
    return {
      ok: false,
      error: `จำนวนเงินต้องอยู่ระหว่าง $${formatMoney(minTip)} ถึง $${formatMoney(maxTip)}`,
    };
  }
  return { ok: true, value };
}

export function shouldHandleEscape(modalMode, submitting) {
  return Boolean(modalMode) && !submitting;
}

export function isStaleModalResponse(activeSpotId, requestSpotId) {
  return !activeSpotId || activeSpotId !== requestSpotId;
}
