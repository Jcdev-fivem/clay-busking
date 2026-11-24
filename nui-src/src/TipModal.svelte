<script>
  import { onMount } from 'svelte';
  import { digitsOnly, formatMoney, parseTipInput, quickTipAmounts } from './format.js';

  let { ui, limits, submitting = false, serverError = '', onClearError, onClose, onSubmit } = $props();

  let rawAmount = $state('');
  let localError = $state('');
  let inputEl;

  let presets = $derived(quickTipAmounts(limits.minTip, limits.maxTip));
  let activeError = $derived(localError || serverError);

  onMount(() => {
    inputEl?.focus();
  });

  function setAmount(next) {
    rawAmount = next;
    localError = '';
    onClearError?.();
  }

  function handleSubmit(event) {
    event.preventDefault();
    if (submitting) return;
    const parsed = parseTipInput(rawAmount, limits.minTip, limits.maxTip);
    if (!parsed.ok) {
      localError = parsed.error;
      return;
    }
    localError = '';
    onSubmit(parsed.value);
  }
</script>

<div class="modal-stage">
  <div class="panel modal-panel" role="dialog" aria-modal="true" aria-labelledby="busking-tip-title">
    <header class="bar">
      <div class="bar-title">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="12" r="9" />
          <path d="M12 7v10M14.5 9.5c0-1.1-1.1-1.8-2.5-1.8s-2.5.7-2.5 1.8c0 2.2 5 1.3 5 3.7 0 1.2-1.1 2-2.5 2s-2.5-.8-2.5-2" />
        </svg>
        <h1 id="busking-tip-title" class="display">{ui.title}</h1>
      </div>
      <button class="exit" type="button" onclick={onClose} disabled={submitting}>
        <kbd>Esc</kbd> ปิด
      </button>
    </header>

    <form onsubmit={handleSubmit}>
      <label class="field" for="busking-tip-input">
        <span>{ui.tipPrompt}</span>
        <div class="input">
          <i aria-hidden="true">$</i>
          <input
            id="busking-tip-input"
            bind:this={inputEl}
            value={rawAmount}
            oninput={(e) => setAmount(digitsOnly(e.currentTarget.value))}
            type="text"
            inputmode="numeric"
            autocomplete="off"
            placeholder={`${formatMoney(limits.minTip)} - ${formatMoney(limits.maxTip)}`}
            disabled={submitting}
          />
        </div>
      </label>

      {#if presets.length > 0}
        <div class="quick" role="group" aria-label="จำนวนลัด">
          {#each presets as amt (amt)}
            <button
              type="button"
              class:on={rawAmount === String(amt)}
              onclick={() => setAmount(String(amt))}
              disabled={submitting}
            >
              {formatMoney(amt)}
            </button>
          {/each}
        </div>
      {/if}

      <p class="notice" role="status" aria-live="polite">
        {#if activeError}
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 8v5M12 16.5v.5M10.3 3.9L2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
          </svg>
          {activeError}
        {/if}
      </p>

      <div class="actions">
        <button type="button" class="btn" onclick={onClose} disabled={submitting}>
          {ui.closeLabel}
        </button>
        <button type="submit" class="btn primary" disabled={submitting}>
          {submitting ? 'กำลังส่ง...' : ui.confirmLabel}
        </button>
      </div>
    </form>
  </div>
</div>
