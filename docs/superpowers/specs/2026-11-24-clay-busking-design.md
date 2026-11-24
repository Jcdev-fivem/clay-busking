# clay-busking: Design & Architecture

ระบบเปิดหมวกและรับทิป (`clay-busking`) สำหรับเซิร์ฟเวอร์ QBox อ้างอิงรูปแบบหน้าตา ฟีเจอร์ และข้อมูลจาก `xCore Busking` โดยปรับให้เข้ากับโครงสร้างและมาตรฐานของ resource ตระกูล `[clay]` (`clay-musicbox`, `clay-banking`)

---

## 1. Intent & Scope

ผู้เล่นสามารถวางหมวกเปิดหมวกในโลกเกมเพื่อให้ผู้เล่นรอบข้างเดินมาทิปเงินสด พร้อมแสดงยอดรวมและอันดับผู้ให้ทิป Top 3 แบบเรียลไทม์บน HUD ด้านขวา และรับเงินก้อนเดียวเมื่อกดเก็บหมวกหรือปิดรอบอัตโนมัติ

### Goals
- เริ่มเปิดหมวกด้วยไอเท็ม `busking_hat` ใน `ox_inventory` และวางที่ไหนก็ได้ (บนพื้น นอกรถ) โดยกันวางซ้อนในระยะขั้นต่ำ
- แสดง HUD ด้านขวากลางแบบสดเมื่ออยู่ในรัศมีจุดเปิดหมวก: ชื่อระบบ, ยอดรวม `รายได้ทั้งหมด $ X`, อันดับ Top 3 ผู้ให้ทิปสะสมรายคน (มงกุฎอันดับ 1/2/3, ชื่อ, ยอดสะสม) และสถานะว่าง `•••`
- กด `[E]` ที่หมวกแยกบทบาทอัตโนมัติ:
  - ผู้เล่นอื่น: เปิด Modal กรอกจำนวนเงินทิป (`Close` / `Confirm`) หักเงินสด ทำท่าก้มหยอดเงินพร้อมเสียง และอัปเดต HUD สดทุกคนในระยะ
  - เจ้าของหมวก: เปิด Modal แสดงยอดรวม (`Close` / `รับเงิน`) กดแล้วรับเงิน ลบหมวก ปิดรอบ และแสดงแจ้งเตือน
- รองรับหลายจุดเปิดหมวกพร้อมกันอย่างอิสระ
- ป้องกันเงินทิปสูญหายและป้องกันบั๊กปั๊มเงินทุกกรณี: เดินออกนอกระยะ, ตัวละครตาย, ออกจากเซิร์ฟเวอร์ (`OnPlayerUnload` / `playerDropped`), และ `onResourceStop` ต้องปิดรอบและจ่ายเงินอัตโนมัติ

### Non-Goals
- ไม่มีฐานข้อมูล (`oxmysql`), ไม่มีประวัติทิปย้อนหลัง, ไม่มีตารางอันดับ Top Tipper ตลอดกาล
- ไม่มีคำสั่งแอดมินลบจุดเปิดหมวกแยก (เพราะจุดจะปิดอัตโนมัติทันทีเมื่อเจ้าของเดินหนี ตาย หรือหลุดเซิร์ฟ จึงไม่ค้างในระบบ)
- ไม่ทำระบบเล่นดนตรีในตัว (เซิร์ฟมี `clay-musicbox` และ `clay-emotemenu` แยกอยู่แล้ว)
- ไม่มีโหมดโซนเปิดหมวกตายตัวในเวอร์ชันแรก (วางได้ทุกที่โดยเว้นระยะห่างระหว่างหมวก)
- ไม่วาด `DrawText3D` บนหมวกและไม่วาดวง marker สีเขียวบนพื้นเป็นค่าเริ่มต้น (เปิดได้ผ่าน `config.lua` หากต้องการภายหลัง)

### Anti-Goals (เงื่อนไขที่ถือว่าล้มเหลวแม้โค้ดรันได้)
- เงินทิปหายเมื่อเจ้าของหลุดเซิร์ฟหรือเดินออกนอกระยะ หรือถูก `ox_inventory` เขียนทับตอน login ใหม่
- กดรับเงินซ้ำหรือกดทิปพร้อมรับเงินแล้วเกิดการจ่ายเงินสองครั้งหรือหักเงินโดยไม่เข้าหมวก
- กิน resmon ฝั่ง client เมื่อไม่มีจุดเปิดหมวกอยู่ใกล้ตัว

---

## 2. Constraints (ข้อจำกัดจริงของเซิร์ฟเวอร์นี้)

1. **`playerDropped` รันหลัง `ox_inventory` teardown**: จากประสบการณ์ใน `clay-musicbox/server/main.lua` หากหักไอเท็มออกจากกระเป๋าตอนวางจะไม่สามารถคืนไอเท็มได้เมื่อผู้เล่นหลุดกะทันหัน
2. **`ox_inventory` sync เงินสดทับตอน login**: จาก `ox_inventory/modules/bridge/qbx/server.lua` (`server.syncInventory`) บัญชี `cash` ผูกกับไอเท็ม `money` ในกระเป๋า การเรียก `qbx_core:AddMoney(offlineCid, 'cash', amount)` ตอนผู้เล่นออฟไลน์จะแก้เฉพาะ `players.money.cash` แต่ไม่แก้ไอเท็มในกระเป๋า เมื่อผู้เล่นกลับมา login ระบบจะเขียนทับ `cash` กลับเป็นยอดเดิม
   - **ทางแก้ที่บังคับใช้**: จ่ายเงินตอนออนไลน์เข้า `Config.Account` (`'cash'`), แต่กรณี fallback ออฟไลน์ (หา `GetPlayer(src)` ไม่เจอแล้ว) ต้องจ่ายเข้า `'bank'` แทนเสมอ เพราะ `'bank'` ไม่ถูก `ox_inventory` เขียนทับ
3. **QBox `GetPlayer` คืนค่า copy**: ต้องอ่านยอดเงินสดใหม่และตรวจ `money.cash >= amount` โดยไม่มี `Wait` หรือ I/O คั่นก่อนเรียก `RemoveMoney` (ตาม pattern ของ `clay-banking`)
4. **มาตรฐาน UI ของ `[clay]`**: ใช้ Svelte 5 + Vite (`nui-src/` build ลง `ui/`), ฟอนต์ `@fontsource/kanit` และ `@fontsource/chakra-petch`, มีโหมด mock สำหรับ `npm run dev`

---

## 3. Approaches Considered

| แนวทาง | กลไกหลัก | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **1. In-Memory + Reusable Item (เลือกใช้)** | เก็บจุดใน memory ฝั่ง server; ไอเท็ม `busking_hat` ตั้ง `consume = 0` ไม่หักจากกระเป๋า แต่ตรวจว่ามีอย่างน้อย 1 ชิ้นและจำกัด 1 จุด/คน | ไม่ทำไอเท็มหายตอนหลุดเซิร์ฟหรือกระเป๋าเต็ม, โค้ดสั้น, ไม่มี SQL overhead | ผู้เล่นยืมหมวกใบเดียวให้เพื่อนวางเพิ่มระหว่างที่จุดตัวเองยังเปิดได้ (แต่ยังจำกัด 1 จุด/คนอยู่ดี) |
| 2. In-Memory + หักไอเท็มตอนวาง | `RemoveItem` ตอนวาง และ `AddItem` ตอนเก็บ (เหมือน `clay-musicbox`) | กันการยืมหมวกใบเดียววางซ้อน | เสียไอเท็มเมื่อหลุดเซิร์ฟกะทันหันหรือกระเป๋าเต็มตอนเดินหนี เว้นแต่จะเพิ่ม DB คืนของ |
| 3. In-Memory + ตาราง `oxmysql` | บันทึกยอดค้างและประวัติทิปลง DB ทุกครั้งที่ทิป | กันเงินหายแม้เครื่องเซิร์ฟดับกะทันหัน (`kill -9`) และต่อยอดสถิติได้ | เพิ่ม SQL write ทุกครั้งที่ทิปและเกินความต้องการจากคลิป |

**เหตุผลที่เลือกแนวทาง 1**: ตรงขอบเขตคลิปทุกข้อ ไม่มีโอกาสทำไอเท็มหายในจังหวะหลุดเซิร์ฟ ไม่เพิ่มตาราง DB และจัดการความเสี่ยงเงินหายทุกเคสปกติได้ด้วย auto-payout + offline `'bank'` fallback

---

## 4. Resource Structure

โครงสร้างตามมาตรฐาน `clay-musicbox` และ `clay-banking`:

```text
clay-busking/
├─ fxmanifest.lua          deps: ox_lib, ox_inventory, qbx_core; ui_page 'ui/index.html'
├─ config.lua              ไอเท็ม, prop, ระยะต่าง ๆ, min..max tip, account, optional visuals, ข้อความ UI
├─ shared/
│  └─ rules.lua            pure functions: ตรวจจำนวนเงิน, ตรวจระยะวางซ้อน, รวมยอดผู้ทิปและจัดอันดับ Top 3
├─ server/
│  ├─ selfcheck.lua        assert ทดสอบ shared/rules.lua ตอน start เมื่อ Config.Debug = true
│  └─ main.lua             registry จุดเปิดหมวก, per-spot/per-player lock, lib.callback, watchdog, lifecycle payout
├─ client/
│  └─ main.lua             ox_inventory export, lib.points stream prop/HUD/[E], anim+sound, NUI bridge
├─ nui-src/                Svelte 5 + Vite + Vitest/node:test
│  ├─ src/
│  │  ├─ App.svelte        จัดการสถานะ HUD card + TipModal + CollectModal + preview controls
│  │  ├─ HudCard.svelte    การ์ดขวากลาง: ชื่อ, รายได้ทั้งหมด, Top 3 มงกุฎ, สถานะว่าง •••
│  │  ├─ TipModal.svelte   กล่องกรอกจำนวนเงินทิปสำหรับคนอื่น
│  │  ├─ CollectModal.svelte กล่องแสดงยอดรวมและปุ่มรับเงินสำหรับเจ้าของ
│  │  ├─ nui.js            ตัวเชื่อม fetch NUI + ตรวจโหมด browser preview
│  │  └─ preview.js        ข้อมูลจำลองสำหรับ npm run dev
│  └─ tests/               unit test format เงิน / parse จำนวนเงินฝั่ง NUI
└─ ui/                     ผลลัพธ์ build จาก nui-src/
```

### `ox_inventory` Item Registration
เพิ่มรายการใน `resources/[ox]/ox_inventory/data/items.lua`:

```lua
['busking_hat'] = {
    label = 'หมวกเปิดหมวก',
    weight = 300,
    stack = false,
    close = true,
    consume = 0,
    description = 'วางลงพื้นเพื่อเปิดหมวกรับทิปจากผู้เล่นรอบข้าง',
    client = { export = 'clay-busking.useBuskingHat' },
},
```

---

## 5. Data Model & Pure Rules

### 5.1 Server In-Memory State (`spots[spotId]`)
```lua
---@class DonorEntry
---@field cid string
---@field name string
---@field amount integer
---@field order integer          -- ลำดับที่ให้ทิปครั้งแรกในรอบนี้ (ใช้ตัดสินเมื่อยอดเท่ากัน)

---@class BuskingSpot
---@field id string              -- เช่น 'busk_1'
---@field ownerCid string
---@field ownerSrc integer
---@field ownerName string
---@field coords { x: number, y: number, z: number }
---@field heading number
---@field total integer          -- ยอดทิปสะสมทั้งหมดในรอบ
---@field donorSeq integer       -- ตัวนับลำดับผู้ทิปรายใหม่
---@field donors table<string, DonorEntry>
---@field top3 { name: string, amount: integer }[]
```

### 5.2 Snapshot ที่ส่งให้ Client (ลด payload ไม่ส่ง `donors` ทั้งก้อน)
```lua
{
    id = spot.id,
    ownerCid = spot.ownerCid,
    coords = spot.coords,
    heading = spot.heading,
    total = spot.total,
    top3 = spot.top3, -- สูงสุด 3 รายการ: { { name = '...', amount = 2360 }, ... }
}
```

### 5.3 กฎใน `shared/rules.lua` (Pure Functions)
- `Rules.validateAmount(raw, minAmount, maxAmount)`: รับเฉพาะจำนวนเต็ม (`math.type(n) == 'integer'` หรือตัวเลขที่ `math.floor(n) == n` และไม่มีทศนิยม/NaN/Inf) ในช่วง `minAmount..maxAmount`
- `Rules.isTooClose(coords, existingSpots, minSpacing)`: คืน `true` หากระยะ 3D จากจุดที่มีอยู่จุดใดจุดหนึ่งน้อยกว่า `minSpacing`
- `Rules.computeTop3(donors)`:
  - จัดเรียงตาม `amount` จากมากไปน้อย
  - ถ้ายอดเท่ากัน ให้คนที่ทำยอด/ให้ทิปก่อน (`order` น้อยกว่า) อยู่ลำดับบน (ตรงกับพฤติกรรมในคลิปที่ `PlayerB` อยู่เหนือ `PlayerC` เมื่อยอด 500 เท่ากัน)
  - คืน array สูงสุด 3 รายการเฉพาะ `{ name, amount }`
- `Rules.fullName(charinfo, fallback)`: รวม `firstname .. ' ' .. lastname` โดย trim ช่องว่าง หากว่างให้ใช้ `fallback`

---

## 6. Network Protocol & Flows

### 6.1 Callbacks & Events

| Channel | ทิศทาง | Input | Output / ผลลัพธ์ |
|---|---|---|---|
| `clay-busking:getAll` | `lib.callback` (C->S) | – | array ของ snapshot ทุกจุดที่เปิดอยู่ (เรียกตอน `OnPlayerLoaded` / `onClientResourceStart`) |
| `clay-busking:start` | `lib.callback` (C->S) | `coords, heading` | `{ ok, spot?, reason?, message? }` + broadcast `clay-busking:syncSpot` |
| `clay-busking:tip` | `lib.callback` (C->S) | `spotId, amount` | `{ ok, spot?, reason?, message? }` + broadcast `clay-busking:syncSpot` |
| `clay-busking:collect` | `lib.callback` (C->S) | `spotId` | `{ ok, total?, reason?, message? }` + broadcast `clay-busking:removeSpot` |
| `clay-busking:ownerLeft` | `RegisterNetEvent` (C->S) | `spotId` | server ตรวจซ้ำว่าเจ้าของอยู่นอกระยะหรือตายจริง แล้วปิดรอบ + auto-payout |
| `clay-busking:syncSpot` | Client Event (S->C `-1`) | `snapshot` | เพิ่มหรืออัปเดตจุดใน client + อัปเดต HUD/Modal หากเปิดอยู่ |
| `clay-busking:removeSpot` | Client Event (S->C `-1`) | `spotId` | ลบ `lib.points`, ลบ prop, ซ่อน HUD/Modal ถ้ากำลังแสดงจุดนี้อยู่ |

### 6.2 Core Flows

1. **วางหมวก (`useBuskingHat`)**:
   - Client ตรวจสถานะพื้นฐาน (ไม่ตาย, ไม่อยู่ในรถ, ไม่ว่ายน้ำ/กำลังตก, ไม่กำลังวางหรือเปิด Modal อยู่)
   - เล่น `lib.progressCircle` + ท่าก้มวาง (`amb@medic@standing@kneel@base` / `base`, ~1000ms)
   - คำนวณพิกัดด้านหน้าตัวละคร (`Config.PlaceDistance`) + `GetGroundZFor_3dCoord` แล้วเรียก `clay-busking:start`
   - Server ตรวจ lock ผู้เล่น, ตรวจ `ox_inventory:GetItemCount(src, Config.ItemName) >= 1`, ตรวจยังไม่เปิดจุดอยู่ (1 จุดต่อ `ownerCid`), ตรวจไม่อยู่ในรถและไม่ตาย, ตรวจพิกัดไม่ไกลจากตัวผู้เล่นเกิน 4.0m, ตรวจ `Rules.isTooClose` กับทุกจุดที่เปิดอยู่ แล้วสร้าง `spot` และ broadcast `syncSpot`

2. **การทิป (`clay-busking:tip`)**:
   - ผู้เล่นเดินเข้าใกล้หมวกของคนอื่น (`<= Config.InteractDistance`) กด `[E]` เปิด `TipModal`
   - กรอกจำนวนเงินแล้วกด `Confirm`
   - Server จับ lock ผู้เล่น + lock จุด:
     - ตรวจจุดยังมีอยู่, ผู้ทิปไม่ใช่เจ้าของ (`tipperCid ~= spot.ownerCid`), ผู้ทิปไม่ตายและไม่อยู่ในรถ, ระยะห่าง `<= Config.InteractDistance + 2.0`, `Rules.validateAmount` ผ่าน
     - อ่าน `qbx_core:GetPlayer(src)` ตรวจ `money[Config.Account] >= amount` แล้วเรียก `RemoveMoney` ทันทีโดยไม่มี yield คั่น
     - อัปเดต `spot.total`, สะสมยอดใน `spot.donors[tipperCid]` (ใช้ชื่อจาก `charinfo` ฝั่ง server), คำนวณ `spot.top3` ใหม่ แล้วปล่อย lock
     - Broadcast `syncSpot` ให้ทุก client
   - Client ผู้ทิปปิด Modal, เล่นท่าก้มหยอดเงิน (`pickup_object` / `pickup_low`) และเล่นเสียงเหรียญ (`PlaySoundFrontend`), แจ้งเตือนหักเงิน

3. **เจ้าของรับเงินและปิดรอบ (`clay-busking:collect`)**:
   - เจ้าของเดินเข้าใกล้หมวกตัวเอง กด `[E]` เปิด `CollectModal` แสดงยอด `รายได้ทั้งหมด $ X`
   - กด `รับเงิน`:
     - Server จับ lock จุด ตรวจว่าเป็น `ownerCid` ของจุดนั้นและอยู่ระยะ `<= Config.InteractDistance + 2.0`
     - **ลบจุดออกจากตาราง (`spots[spotId] = nil`) ก่อนจ่ายเงิน** เพื่อกัน double-collect 100%
     - Broadcast `removeSpot`
     - ถ้า `total > 0`: จ่ายเงินเข้า `Config.Account` ผ่าน `qbx_core:AddMoney(src, Config.Account, total, 'clay-busking-collect')` และแจ้ง toast `คุณได้รับเงินจำนวน $X จากการเปิดหมวก`
     - ถ้า `total == 0`: แจ้ง `เก็บหมวกเปิดหมวกแล้ว`

4. **ปิดรอบและจ่ายเงินอัตโนมัติ (Auto-End / Fail-Safe Payout)**:
   - เงื่อนไขที่ปิดรอบอัตโนมัติ:
     - เจ้าของเดินห่างจากหมวกเกิน `Config.AutoEndRadius` (ตรวจทั้งจาก client loop 500ms ที่ส่ง `ownerLeft` และ server watchdog ทุก 2000ms เฉพาะตอนมีจุดเปิดอยู่ เพื่อกัน client ค้างหรือถูกแก้)
     - เจ้าของตาย (`IsEntityDead` / `LocalPlayer.state.isDead` หรือฝั่ง server `metadata.isdead` / `metadata.inlaststand` / `GetEntityHealth(ped) <= 0`)
     - `QBCore:Server:OnPlayerUnload` (รันก่อน inventory teardown -> จ่ายเข้า `Config.Account` ได้ตรง)
     - `playerDropped` (fallback หากหลุดกะทันหันโดยไม่ผ่าน unload -> หาก `GetPlayer(ownerSrc)` เป็น nil ให้จ่ายเข้า `'bank'` ด้วย `AddMoney(ownerCid, 'bank', total, 'clay-busking-offline')` เพื่อไม่ให้ `ox_inventory` เขียนทับตอน login)
     - `onResourceStop` (วนปิดทุกจุดที่ค้างและจ่ายเงินคืนเจ้าของทุกคน: ออนไลน์เข้า `Config.Account`, ออฟไลน์เข้า `'bank'`)

---

## 7. Client Spatial & UI Architecture

### 7.1 Spatial Handling (`lib.points`)
- ทุกจุดใน `spots` สร้าง `lib.points.new` ระยะ `Config.PropSpawnDistance` (`60.0`m):
  - `onEnter` / `onExit`: โหลดและสร้าง/ลบ prop หมวก (`CreateObject` local client-side, `PlaceObjectOnGroundProperly`, `FreezeEntityPosition`, `SetEntityAsMissionEntity` — เหมือน `clay-musicbox` ไม่สร้าง networked entity เปลือง OneSync slot)
  - `nearby`: เช็กเฉพาะจุดที่ใกล้สุดในระยะ:
    - ระยะ `<= Config.HudRadius` (`10.0`m): อัปเดต `activeHudSpotId` เพื่อแสดง HUD ขวากลาง (ถ้ามีหลายจุดซ้อนรัศมี HUD ให้เลือกจุดที่ใกล้ผู้เล่นที่สุด)
    - ระยะ `<= Config.InteractDistance` (`2.2`m) และไม่ได้เปิด Modal / ไม่อยู่ในรถ / ไม่ตาย: แสดง `lib.showTextUI('[E] เปิดหมวก / ทิป')` (ปรับข้อความตามบทบาทเจ้าของหรือผู้ชม) และรับปุ่ม `[E]`
    - Optional (ปิดเป็นค่าเริ่มต้นใน `config.lua`): หากเปิด `Config.ShowZoneMarker` วาดวงกลมพื้นรัศมี `Config.HudRadius`, หากเปิด `Config.Show3DText` วาดข้อความ `Tip $ X` เหนือหมวกเฉพาะตอนอยู่ใน `Config.HudRadius`
- เมื่อไม่มีจุดเปิดหมวกในระยะ `60.0`m client ไม่รัน loop เฟรมใดเลย (resmon 0.00ms)

### 7.2 UI Layout (อ้างอิงจากคลิป `xCore Busking`)

```text
+-------------------------------------------------------------------+
|                                                                   |
|                                               +-----------------+ |
|                                               | [hat] Busking   | |
|                   [ Centered Modal ]          |-----------------| |
|              +-------------------------+      | รายได้ทั้งหมด $ 5860 |
|              | [hat] Clay Busking      |      | [1] PlayerD 2360| |
|              |                         |      | [2] PlayerA 2000| |
|              | กรุณาใส่จำนวนเงินที่ต้องการ  |      | [3] PlayerB 1000| |
|              | [       1000          ] |      +-----------------+ |
|              |   [ Close ] [ Confirm ] |         (ว่างแสดง •••)   |
|              +-------------------------+                          |
|                                                                   |
|                    [E] กดเพื่อเปิดเมนูเปิดหมวก                        |
+-------------------------------------------------------------------+
```

- **HudCard (ขวากลาง, `pointer-events: none`, ไม่แย่ง NUI focus)**:
  - โทนเข้มโปร่งแสง ขอบโค้งมน สะอาดตาตามคลิปและฟอนต์ `Kanit` / `Chakra Petch`
  - Header: ไอคอน + ชื่อ (`Config.Ui.title`)
  - เส้นคั่นบาง + แถว `รายได้ทั้งหมด $ <formatNumber(total)>`
  - ถ้า `top3.length === 0`: แสดง `•••` ตรงกลาง
  - ถ้ามีผู้ทิป: แสดง 1–3 แถว แต่ละแถวมีไอคอนมงกุฎแยกสี (ทอง `#F5C542`, ส้มทองแดง `#E68A3E`, เขียว `#4ADE80`), ชื่อผู้ทิป (truncate ถ้าชื่อยาว), และ badge ตัวเลขยอดสะสมรายคน
- **TipModal (กลางจอ, มี NUI focus)**:
  - Header ชื่อระบบ, ข้อความ `กรุณาใส่จำนวนเงินที่ต้องการ`, input ตัวเลข (รับเฉพาะจำนวนเต็มบวก มี autofocus และรองรับกด Enter), แสดงข้อความ error สั้น ๆ ใต้ช่องถ้ายอดไม่ถูกต้องหรือเงินไม่พอ, ปุ่ม `Close` และ `Confirm` (disable ระหว่างรอ server ตอบกันกดเบิ้ล)
- **CollectModal (กลางจอ, มี NUI focus)**:
  - Header ชื่อระบบ, ข้อความ `รายได้ทั้งหมด $ <formatNumber(total)>`, ปุ่ม `Close` และ `รับเงิน` (disable ระหว่างรอ server ตอบ)
- **Close Safety**: กด `ESC`, กด `Close`, เดินออกห่างเกิน `Config.InteractDistance + 2.0`, ตัวละครตาย, หรือจุดถูกปิด ต้องปลด `SetNuiFocus(false, false)` และปิด Modal ทันที

---

## 8. Security & Money Safety Matrix

| ความเสี่ยง | การป้องกัน |
|---|---|
| ส่งจำนวนทิปติดลบ / 0 / ทศนิยม / NaN / string | `Rules.validateAmount` ฝั่ง server ตรวจจำนวนเต็มและช่วง `MinTip..MaxTip` |
| กด `Confirm` หรือ `รับเงิน` รัว ๆ | Lock ต่อ `src` และ lock ต่อ `spotId` + disable ปุ่มฝั่ง NUI ระหว่างรอ callback |
| ทิปพร้อมจังหวะเจ้าของกดรับเงิน | ใช้ spot lock เดียวกัน; `collect` ลบ `spots[spotId] = nil` ก่อนจ่ายเงิน เงินทิปจะไม่ค้างและไม่ถูกจ่ายซ้ำ |
| เงินไม่พอแล้วหักติดลบ | ตรวจ `player.PlayerData.money[Config.Account] >= amount` หลัง lock และไม่มี yield คั่นก่อน `RemoveMoney` |
| Client ปลอมชื่อผู้ทิปหรือ citizenid | Server อ่าน `citizenid` และ `charinfo` จาก `qbx_core:GetPlayer(src)` เสมอ ไม่รับจาก client |
| ทิปหรือรับเงินจากระยะไกล / ทิปหมวกตัวเอง | Server ตรวจระยะ 3D จาก `GetEntityCoords(GetPlayerPed(src))` และตรวจ `tipperCid ~= spot.ownerCid` |
| เจ้าของหลุดเซิร์ฟแล้วเงินทิปถูก `ox_inventory` เขียนทับ | `OnPlayerUnload` จ่าย `cash` ก่อน teardown; `playerDropped` fallback จ่ายเข้า `'bank'` เมื่อ `GetPlayer` เป็น nil |
| เจ้าของค้างหรือโกง client ไม่ส่ง `ownerLeft` | Server watchdog ตรวจระยะและสถานะมีชีวิตของเจ้าของทุก 2 วินาทีเมื่อมีจุดเปิดอยู่ |
| Audit log | ส่ง reason ชัดเจน (`clay-busking-tip`, `clay-busking-collect`, `clay-busking-auto`, `clay-busking-offline`) เข้า logger ของ `qbx_core` |

---

## 9. Configuration (`config.lua`)

```lua
Config = {
    Debug = false,
    ItemName = 'busking_hat',
    PropModel = 'prop_ld_hat_01',
    PropZOffset = 0.0,

    Account = 'cash',              -- บัญชีหลักที่ใช้ทิปและรับเงินตอนออนไลน์ ('cash' หรือ 'bank')
    OfflineFallbackAccount = 'bank', -- บัญชีรับเงินเมื่อเจ้าของออฟไลน์แล้ว (กัน ox_inventory เขียนทับ cash)

    MaxSpotsPerPlayer = 1,
    MinSpotSpacing = 6.0,          -- ระยะห่างขั้นต่ำระหว่างหมวกสองใบ
    PlaceDistance = 1.0,
    PlaceDurationMs = 1000,
    PropSpawnDistance = 60.0,
    HudRadius = 10.0,              -- ระยะแสดง HUD ขวากลาง
    InteractDistance = 2.2,        -- ระยะกด [E]
    AutoEndRadius = 14.0,          -- เจ้าของออกเกินระยะนี้ปิดรอบและจ่ายเงินอัตโนมัติ
    ServerWatchdogMs = 2000,

    MinTip = 1,
    MaxTip = 100000,

    -- Optional visuals (ปิดไว้ตามค่าเริ่มต้นเพื่อลด resmon และความรก)
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
```

---

## 10. Known Shortcuts & Trade-offs

- `shortcut: ไม่เก็บยอดทิปลง MySQL; หากเครื่องเซิร์ฟดับกะทันหัน (kill -9) ก่อน onResourceStop รัน เงินที่ค้างในหมวกรอบนั้นจะหาย — อัปเกรดเป็นตาราง pending payout เมื่อยอดทิปต่อรอบสูงหรือมีปัญหาเซิร์ฟล่มบ่อย`
- `shortcut: ไอเท็ม busking_hat ตั้ง consume = 0 ไม่หักออกจากกระเป๋า เพื่อกันไอเท็มหายตอน playerDropped — อัปเกรดเป็นการหักไอเท็มพร้อมตารางคืนของเมื่อ login หากต้องการห้ามยืมหมวกใบเดียวระหว่างเพื่อน`
- `shortcut: broadcast syncSpot/removeSpot ส่งไปทุกคน (-1) เพราะ payload เล็กมากและเปลี่ยนเฉพาะตอนวาง/ทิป/เก็บ — อัปเกรดเป็นส่งเฉพาะผู้เล่นในระยะหรือ statebag หากเซิร์ฟมีจุดเปิดหมวกพร้อมกันหลายสิบจุด`

---

## 11. Verification Plan

1. **Automated Unit Checks**:
   - `server/selfcheck.lua` (รันเมื่อ `Config.Debug = true`): ตรวจ `Rules.validateAmount` (ติดลบ, 0, ทศนิยม, string, เกิน max, ขอบ min/max), `Rules.isTooClose`, `Rules.computeTop3` (สะสมรายคน, อันดับ 4 แซงขึ้น 1, ยอดเท่ากันเรียงตามลำดับมาก่อน)
   - `nui-src`: `npm test` (parse จำนวนเต็ม, format ตัวเลขคั่นลูกน้ำ) และ `npm run build` ออก `ui/` โดยไม่มี error
2. **UI Preview**: `npm run dev` ทดสอบ HUD ว่าง (`•••`), Top 1–3, แซงอันดับ, TipModal (รวม validation และ error state), CollectModal
3. **In-Game QBox Scenarios**:
   - วางหมวกด้วยไอเท็ม `busking_hat` -> วางซ้ำใบที่ 2 (ต้องไม่ผ่าน) -> วางใกล้หมวกคนอื่นเกิน `MinSpotSpacing` (ต้องไม่ผ่าน)
   - เดินเข้าออกระยะ `HudRadius` (HUD ขึ้นและหายถูกต้อง)
   - ผู้เล่นหลายคนทิปซ้ำและยอดแซงกัน (Top 3 เรียงสดถูกต้อง, หัก `cash` ถูกต้อง, เจ้าของทิปตัวเองไม่ได้)
   - เจ้าของกด `[E]` -> `รับเงิน` (ได้เงินตรงยอด, toast ขึ้น, หมวกและ HUD หาย) และทดสอบรับเงินตอนยอด `0`
   - เจ้าของเดินออกเกิน `AutoEndRadius` (auto-end + auto-payout)
   - เจ้าของตาย / ออกจากเซิร์ฟเวอร์ / restart resource ระหว่างมียอดค้าง (ได้รับเงินครบและเมื่อกลับมา login เงินไม่ถูก `ox_inventory` เขียนทับ)

---

## 12. Left to the Builder

- เลือกและปรับค่า `PropModel` / `PropZOffset` จาก prop หมวกที่มีใน GTA V (`prop_ld_hat_01` หรือ prop หมวกอื่นที่วางหงาย/ตั้งบนพื้นได้สวยไม่จมพื้น)
- เลือก GTA frontend sound name ที่ฟังชัดที่สุดสำหรับจังหวะหยอดทิป (`PlaySoundFrontend`)
- รายละเอียด CSS (ความโปร่งแสง, shadow, transition การเลื่อนอันดับ Top 3) ให้เข้ากับชุด UI ของ `[clay]`
