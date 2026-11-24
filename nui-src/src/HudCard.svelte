<script>
  import { formatMoney } from './format.js';

  let { spot, ui } = $props();

  const rankColors = ['var(--warn)', 'var(--rank-2)', 'var(--in)'];
</script>

<aside class="panel hud-panel" aria-label={ui.title}>
  <header class="bar hud-bar">
    <div class="bar-title">
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v10M14.5 9.5c0-1.1-1.1-1.8-2.5-1.8s-2.5.7-2.5 1.8c0 2.2 5 1.3 5 3.7 0 1.2-1.1 2-2.5 2s-2.5-.8-2.5-2" />
      </svg>
      <h2 class="display">{ui.title}</h2>
    </div>
  </header>

  <div class="hud-summary">
    <span class="label">{ui.totalLabel}</span>
    <strong class="display hud-total">${formatMoney(spot.total)}</strong>
  </div>

  <div class="hud-board">
    {#if !spot.top3 || spot.top3.length === 0}
      <div class="hud-empty">
        <span class="dots" aria-hidden="true"><span></span><span></span><span></span></span>
        <span>ยังไม่มีผู้ให้ทิป</span>
      </div>
    {:else}
      <ul class="top-rows" aria-label="ผู้ให้ทิปสูงสุด">
        {#each spot.top3 as donor, idx (donor.name + ':' + idx)}
          <li class="top-row">
            <span class="rank-icon" style:color={rankColors[idx] || rankColors[2]} aria-label={`อันดับ ${idx + 1}`}>
              <svg viewBox="0 0 24 24" aria-hidden="true">
                <path d="M3 18h18M4 15l2-8 4.5 3.5L12 5l1.5 5.5L18 7l2 8H4z" />
              </svg>
            </span>
            <span class="donor-name">{donor.name}</span>
            <span class="donor-amt display">${formatMoney(donor.amount)}</span>
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</aside>

<style>
  .hud-panel {
    position: fixed;
    right: 1.5rem;
    top: 50%;
    transform: translateY(-50%);
    z-index: 10;
    width: 19.5rem;
    padding: 0.9rem 1.05rem 1rem;
    pointer-events: none;
    animation: hud-in 0.2s var(--ease-out);
  }

  @keyframes hud-in {
    from {
      opacity: 0;
      transform: translateY(calc(-50% + 0.45rem));
    }
  }

  .hud-bar {
    min-height: 1.6rem;
    margin-bottom: 0.65rem;
  }

  .hud-bar h2 {
    font-size: 1rem;
  }

  .hud-summary {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    padding-bottom: 0.75rem;
    border-bottom: 1px solid var(--line);
  }

  .hud-total {
    font-size: 1.9rem;
    font-weight: 700;
    line-height: 1.05;
    letter-spacing: 0.01em;
    color: var(--accent-text);
  }

  .hud-board {
    padding-top: 0.7rem;
  }

  .hud-empty {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 0.65rem;
    border-radius: 0.35rem;
    background: var(--raise);
    font-size: 0.86rem;
    color: var(--muted);
  }

  .dots {
    display: inline-flex;
    gap: 0.3rem;
  }

  .dots span {
    width: 0.35rem;
    height: 0.35rem;
    border-radius: 50%;
    background: var(--muted);
    opacity: 0.6;
  }

  .top-rows {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .top-row {
    display: grid;
    grid-template-columns: 1.25rem minmax(0, 1fr) auto;
    align-items: center;
    gap: 0.55rem;
    padding: 0.46rem 0.65rem;
    border-radius: 0.35rem;
    background: var(--raise);
  }

  .rank-icon {
    display: grid;
    place-items: center;
  }

  .rank-icon svg {
    width: 1rem;
    height: 1rem;
  }

  .donor-name {
    min-width: 0;
    font-size: 0.92rem;
    font-weight: 500;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .donor-amt {
    font-size: 0.94rem;
    font-weight: 700;
    color: var(--in);
    text-align: right;
  }
</style>
