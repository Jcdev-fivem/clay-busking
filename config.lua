Config = {
    Debug = false,
    ItemName = 'busking_hat',
    PropModel = 'prop_ld_hat_01',
    PropZOffset = 0.0,

    Account = 'cash',
    -- Fallback when owner is already offline (playerDropped after unload) so ox_inventory sync never overwrites cash on next login.
    OfflineFallbackAccount = 'bank',

    MaxSpotsPerPlayer = 1,
    MinSpotSpacing = 6.0,
    PlaceDistance = 1.0,
    PlaceDurationMs = 1000,
    PropSpawnDistance = 60.0,
    HudRadius = 10.0,
    InteractDistance = 2.2,
    AutoEndRadius = 14.0,
    ServerWatchdogMs = 2000,

    MinTip = 1,
    MaxTip = 100000,

    -- Optional world visuals (off by default to keep resmon minimal and scenes uncluttered).
    Show3DText = false,
    ShowZoneMarker = false,

    Ui = {
        title = 'Clay Busking',
        totalLabel = 'รายได้ทั้งหมด',
        tipPrompt = 'กรุณาใส่จำนวนเงินที่ต้องการ',
        closeLabel = 'Close',
        confirmLabel = 'Confirm',
        collectLabel = 'รับเงิน',
    },
}
