<script>
  import { formatMoney } from './format.js';

  let { spot, ui, submitting = false, serverError = '', onClose, onCollect } = $props();

  let hasTips = $derived((spot.total || 0) > 0);
</script>

<div class="modal-stage">
  <div class="panel modal-panel" role="dialog" aria-modal="true" aria-labelledby="busking-collect-title">
    <header class="bar">
      <div class="bar-title">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="12" r="9" />
          <path d="M12 7v10M14.5 9.5c0-1.1-1.1-1.8-2.5-1.8s-2.5.7-2.5 1.8c0 2.2 5 1.3 5 3.7 0 1.2-1.1 2-2.5 2s-2.5-.8-2.5-2" />
        </svg>
        <h1 id="busking-collect-title" class="display">{ui.title}</h1>
      </div>
      <button class="exit" type="button" onclick={onClose} disabled={submitting}>
        <kbd>Esc</kbd> ปิด
      </button>
    </header>

    <div class="collect-summary">
      <span class="label">{ui.totalLabel}</span>
      <strong class="display collect-balance">${formatMoney(spot.total)}</strong>
      <p class="collect-hint">
        {hasTips ? 'กดรับเงินเพื่อเก็บหมวกและรับเงินสดเข้าตัว' : 'ยังไม่มีรายได้ กดยืนยันเพื่อเก็บหมวก'}
      </p>
    </div>

    <p class="notice" role="status" aria-live="polite">
      {#if serverError}
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M12 8v5M12 16.5v.5M10.3 3.9L2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
        </svg>
        {serverError}
      {/if}
    </p>

    <div class="actions">
      <button type="button" class="btn" onclick={onClose} disabled={submitting}>
        {ui.closeLabel}
      </button>
      <button type="button" class="btn primary" onclick={onCollect} disabled={submitting}>
        {submitting ? 'กำลังดำเนินการ...' : (hasTips ? ui.collectLabel : 'เก็บหมวก')}
      </button>
    </div>
  </div>
</div>

<style>
  .collect-summary {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    padding: 0.7rem 0.1rem 0.9rem;
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
  }

  .collect-balance {
    font-size: 2.5rem;
    font-weight: 700;
    line-height: 1.05;
    letter-spacing: 0.01em;
    color: var(--accent-text);
  }

  .collect-hint {
    margin-top: 0.2rem;
    font-size: 0.86rem;
    color: var(--muted);
  }
</style>
