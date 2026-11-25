# GenLayer — Generative Layer (Solidity)

Kontrak ERC721: pengguna mencetak **generative layer** unik dari hash data
eksternal (iklim, suhu, cuaca, atau data lain). Setiap layer punya ID unik,
metadata JSON, dan bisa diverifikasi on-chain.

## File

- `GenLayer.sol` — kontrak utama (Solidity ^0.8.24, OpenZeppelin v5)

## Dependensi

- `@openzeppelin/contracts` v5 (`ERC721URIStorage`, `Ownable`, `ReentrancyGuard`)

## Cara compile & deploy (Remix, tanpa install apa-apa)

1. Buka https://remix.ethereum.org
2. Buat file `GenLayer.sol`, paste isi kontrak.
3. Tab **Solidity Compiler** → pilih compiler 0.8.24+ → **Compile**.
   (Import OpenZeppelin di Remix otomatis diambil dari GitHub.)
4. Tab **Deploy & Run** → pilih network testnet (mis. Sepolia) →
   **Deploy**. Akun deployer jadi owner (yang bisa atur fee & withdraw).

## Cara pakai

```js
// 1. Hash data eksternal off-chain (contoh: JSON cuaca dari API)
//    inputHash = keccak256(dataMentah)

// 2. Siapkan metadata JSON, upload ke IPFS, dapatkan URI:
//    metadataURI = "ipfs://.../1.json"

// 3. Cek fee dulu (gratis, view):
//    calculateFee(CUACA, 10)  -> 0.0022 ether

// 4. Mint (kirim ETH >= fee):
//    mintLayer(inputHash, CUACA, 10, metadataURI)  -> tokenId

// 5. Verifikasi kapan pun (gratis, view):
//    verifyLayer(tokenId, inputHash)  -> true / false
```

## Fee dinamis

Rumus: `fee = baseFee + (complexity × feePerUnit × multiplier) / 100`

| Pengaturan | Default |
|---|---|
| `baseFee` | 0,001 ETH |
| `feePerUnit` | 0,0001 ETH per poin kompleksitas |
| Pengali IKLIM / SUHU | 100% (1x) |
| Pengali CUACA | 120% (1,2x) |
| Pengali CUSTOM | 150% (1,5x) |

Contoh (default): kompleksitas 10, CUACA → 0,001 + (10 × 0,0001 × 120)/100
= **0,0022 ETH**. Kompleksitas 100, CUSTOM → **0,016 ETH**.

Kelebihan bayar otomatis dikembalikan (refund) di `mintLayer()`.

**Catatan:** fee ini adalah biaya mint kontrak (dalam ETH), bukan gas
network. Gas network tetap dibayar terpisah seperti transaksi biasa.

## Fungsi utama

| Fungsi | Keterangan |
|---|---|
| `mintLayer(inputHash, dataType, complexity, metadataURI)` | Cetak layer baru (payable). Validasi: hash tidak nol, hash belum dipakai, kompleksitas 1–100, metadata tidak kosong, fee cukup. |
| `calculateFee(dataType, complexity)` | Hitung fee mint (view). |
| `verifyLayer(tokenId, inputHash)` | Verifikasi asal-usul layer (view). |
| `getLayer(tokenId)` | Ambil semua data layer (view). |
| `getLayersByCreator(creator)` | Daftar ID layer milik satu alamat (view). |
| `totalLayers()` | Jumlah layer yang sudah dicetak (view). |
| `isInputHashUsed(inputHash)` | Cek hash sudah dipakai atau belum (view). |
| `updateMetadata(tokenId, newURI)` | Ganti metadata JSON (pemilik layer saja). |
| `setBaseFee / setFeePerUnit / setTypeMultiplier` | Atur fee (owner saja). |
| `withdrawFees()` | Tarik fee terkumpul (owner saja). |

## Aturan penting

- **Satu hash = satu layer.** `inputHash` yang sama tidak bisa di-mint dua
  kali — ini yang bikin setiap layer unik dan tidak bisa diduplikasi.
- **verificationHash** mengikat `inputHash + pembuat + tipe data +
  kompleksitas + ID token`. Kalau satu saja berubah, verifikasi gagal.
- **Metadata JSON** disimpan sebagai `tokenURI` (standar ERC721), jadi
  marketplace/wallet bisa membacanya. Isi metadata bebas — nama, deskripsi,
  atribut iklim/suhu/cuaca, link gambar, dan lain-lain.
- **Update metadata tidak merusak bukti asal-usul**, karena metadata bukan
  bagian dari `verificationHash`.

## Data eksternal: dari mana hash-nya?

Kontrak ini **tidak mengambil data cuaca sendiri** — hash dibuat off-chain
dari data mentah (mis. respons JSON API cuaca, lalu `keccak256`). Kontrak
hanya memvalidasi dan mengikat hash itu ke layer.

Kalau mau data masuk on-chain secara otomatis (tanpa perantara manual),
langkah berikutnya adalah oracle, mis. **Chainlink Functions** — kontrak
meminta data cuaca, oracle mengembalikan hash-nya, lalu `mintLayer()`
dipanggil dengan hash tersebut.
