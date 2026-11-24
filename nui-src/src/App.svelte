<script>
  import { onMount } from 'svelte';
  import { inGame, isPreview, nui } from './nui.js';
  import { isStaleModalResponse, shouldHandleEscape } from './format.js';
  import { DEFAULT_UI, createEmptyPreviewSpot, createPopulatedPreviewSpot } from './preview.js';
  import HudCard from './HudCard.svelte';
  import TipModal from './TipModal.svelte';
  import CollectModal from './CollectModal.svelte';

  let ui = $state({ ...DEFAULT_UI });
  let hudSpot = $state(isPreview ? createPopulatedPreviewSpot() : null);
  let hidePreviewBar = $state(false);

  let modalMode = $state(null); // 'tip' | 'collect' | null
  let modalSpot = $state(null);
  let limits = $state({ minTip: 1, maxTip: 100000 });
  let submitting = $state(false);
  let serverError = $state('');

  function mergeUi(nextUi) {
    if (nextUi && typeof nextUi === 'object') {
      ui = { ...DEFAULT_UI, ...nextUi };
    }
  }

  function closeModalLocal(notifyClient = true) {
    modalMode = null;
    modalSpot = null;
    submitting = false;
    serverError = '';
    if (notifyClient && inGame) {
      void nui('close');
    }
  }

  async function submitTip(amount) {
    if (!modalSpot || submitting) return;
    if (isPreview) {
      const nextTotal = (hudSpot?.total || 0) + amount;
      const nextTop3 = [
        { name: 'PreviewTipper', amount },
        ...(hudSpot?.top3 || []),
      ]
        .sort((a, b) => b.amount - a.amount)
        .slice(0, 3);
      hudSpot = { id: modalSpot.id, total: nextTotal, top3: nextTop3 };
      closeModalLocal(false);
      return;
    }

    const targetSpotId = modalSpot.id;
    submitting = true;
    serverError = '';
    const res = await nui('tip', { spotId: targetSpotId, amount });
    if (isStaleModalResponse(modalSpot?.id, targetSpotId)) return;
    submitting = false;
    if (!res || !res.ok) {
      serverError = res?.message || 'ให้ทิปไม่สำเร็จ';
      return;
    }
    closeModalLocal(false);
  }

  async function submitCollect() {
    if (!modalSpot || submitting) return;
    if (isPreview) {
      hudSpot = null;
      closeModalLocal(false);
      return;
    }

    const targetSpotId = modalSpot.id;
    submitting = true;
    serverError = '';
    const res = await nui('collect', { spotId: targetSpotId });
    if (isStaleModalResponse(modalSpot?.id, targetSpotId)) return;
    submitting = false;
    if (!res || !res.ok) {
      serverError = res?.message || 'รับเงินไม่สำเร็จ';
      return;
    }
    closeModalLocal(false);
  }

  onMount(() => {
    if (isPreview) {
      const params = new URLSearchParams(window.location.search);
      const raw = params.get('preview') || '';
      const clean = params.get('clean') === '1' || raw.endsWith('-clean');
      const mode = raw.endsWith('-clean') ? raw.slice(0, -6) : raw;
      hidePreviewBar = clean;
      if (mode === 'tip') {
        modalMode = 'tip';
        modalSpot = hudSpot || createPopulatedPreviewSpot();
      } else if (mode === 'collect') {
        modalMode = 'collect';
        modalSpot = hudSpot || createPopulatedPreviewSpot();
      } else if (mode === 'empty') {
        hudSpot = createEmptyPreviewSpot();
      }
    }

    function onMessage(event) {
      const msg = event.data;
      if (!msg || typeof msg !== 'object') return;
      mergeUi(msg.ui);

      if (msg.action === 'hud') {
        hudSpot = msg.spot || null;
      } else if (msg.action === 'openModal') {
        modalMode = msg.mode === 'collect' ? 'collect' : 'tip';
        modalSpot = msg.spot || null;
        if (msg.limits) {
          limits = {
            minTip: Number(msg.limits.minTip) || 1,
            maxTip: Number(msg.limits.maxTip) || 100000,
          };
        }
        submitting = false;
        serverError = '';
      } else if (msg.action === 'updateModal') {
        if (modalSpot && msg.spot && modalSpot.id === msg.spot.id) {
          modalSpot = msg.spot;
        }
      } else if (msg.action === 'closeModal') {
        closeModalLocal(false);
      }
    }

    function onKeydown(event) {
      if (event.key === 'Escape' && shouldHandleEscape(modalMode, submitting)) {
        event.preventDefault();
        closeModalLocal(true);
      }
    }

    window.addEventListener('message', onMessage);
    window.addEventListener('keydown', onKeydown);
    if (inGame) void nui('ready');

    return () => {
      window.removeEventListener('message', onMessage);
      window.removeEventListener('keydown', onKeydown);
    };
  });
</script>

{#if isPreview}
  <div class="preview-backdrop" aria-hidden="true"></div>
{/if}

{#if hudSpot}
  <HudCard spot={hudSpot} {ui} />
{/if}

{#if modalMode === 'tip' && modalSpot}
  <TipModal
    {ui}
    {limits}
    {submitting}
    {serverError}
    onClearError={() => { serverError = ''; }}
    onClose={() => closeModalLocal(true)}
    onSubmit={submitTip}
  />
{:else if modalMode === 'collect' && modalSpot}
  <CollectModal
    spot={modalSpot}
    {ui}
    {submitting}
    {serverError}
    onClose={() => closeModalLocal(true)}
    onCollect={submitCollect}
  />
{/if}

{#if isPreview && !hidePreviewBar}
  <div class="preview-bar">
    <button type="button" onclick={() => { hudSpot = createEmptyPreviewSpot(); }}>Empty HUD</button>
    <button type="button" onclick={() => { hudSpot = createPopulatedPreviewSpot(); }}>Top 3 HUD</button>
    <button type="button" onclick={() => { modalMode = 'tip'; modalSpot = hudSpot || createPopulatedPreviewSpot(); }}>Tip Modal</button>
    <button type="button" onclick={() => { modalMode = 'collect'; modalSpot = hudSpot || createPopulatedPreviewSpot(); }}>Collect Modal</button>
    <button type="button" onclick={() => { hudSpot = null; closeModalLocal(false); }}>Hide All</button>
  </div>
{/if}

<style>
  .preview-bar {
    position: fixed;
    left: 1rem;
    bottom: 1rem;
    z-index: 30;
    display: flex;
    gap: 0.35rem;
    padding: 0.45rem;
    border-radius: var(--radius);
    background: var(--surface);
    border: 1px solid var(--line);
  }

  .preview-bar button {
    height: 2rem;
    padding: 0 0.7rem;
    border-radius: 0.35rem;
    background: var(--raise);
    color: var(--muted);
    font-size: 0.84rem;
    font-weight: 500;
  }

  .preview-bar button:hover {
    background: var(--raise-hover);
    color: var(--text);
  }
</style>
