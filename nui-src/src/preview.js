export const DEFAULT_UI = {
  title: 'Clay Busking',
  totalLabel: 'รายได้ทั้งหมด',
  tipPrompt: 'กรุณาใส่จำนวนเงินที่ต้องการ',
  closeLabel: 'Close',
  confirmLabel: 'Confirm',
  collectLabel: 'รับเงิน',
};

export function createEmptyPreviewSpot() {
  return { id: 'preview_1', total: 0, top3: [] };
}

export function createPopulatedPreviewSpot() {
  return {
    id: 'preview_1',
    total: 5860,
    top3: [
      { name: 'PlayerD', amount: 2360 },
      { name: 'PlayerA', amount: 2000 },
      { name: 'PlayerB', amount: 1000 },
    ],
  };
}
