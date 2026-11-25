// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// GenLayer — Generative Layer berbasis hash data eksternal (iklim, suhu, cuaca).
// Setiap layer adalah NFT ERC721: ID unik, metadata JSON (via tokenURI),
// dan bisa diverifikasi on-chain lewat verificationHash.
//
// Alur:
//   1. Data eksternal (mis. JSON cuaca dari API) di-hash off-chain:
//      inputHash = keccak256(data)
//   2. Pengguna memanggil mintLayer() dengan inputHash + metadataURI.
//   3. Kontrak memvalidasi hash, menghitung fee dinamis dari kompleksitas,
//      lalu mencetak NFT layer dengan verificationHash yang mengikat
//      hash + pembuat + tipe data + kompleksitas + ID token.
//   4. Siapa pun bisa memverifikasi lewat verifyLayer() tanpa percaya siapa pun.
//
// Dependensi: OpenZeppelin Contracts v5
//   npm install @openzeppelin/contracts
//   (di Remix: import langsung dari GitHub, lihat README.md)

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GenLayer is ERC721URIStorage, Ownable, ReentrancyGuard {
    // ------------------------------------------------------------------------
    // Tipe data
    // ------------------------------------------------------------------------

    /// @notice Jenis data eksternal yang jadi sumber layer.
    enum DataType {
        IKLIM, // data iklim jangka panjang
        SUHU, // suhu
        CUACA, // pola cuaca
        CUSTOM // data lain apa pun
    }

    /// @notice Satu generative layer. Disimpan on-chain per tokenId.
    struct GenerativeLayer {
        uint256 id; // ID unik layer (= tokenId NFT)
        address creator; // pembuat layer
        bytes32 inputHash; // hash data eksternal (keccak256 dari data mentah)
        bytes32 verificationHash; // hash verifikasi (mengikat semua field)
        DataType dataType; // jenis data sumber
        uint256 complexity; // kompleksitas layer (1-100)
        string metadataURI; // URI metadata JSON (mis. ipfs://...)
        uint256 timestamp; // waktu mint (block.timestamp)
    }

    // ------------------------------------------------------------------------
    // Konstanta & konfigurasi fee
    // ------------------------------------------------------------------------

    uint256 public constant MIN_COMPLEXITY = 1;
    uint256 public constant MAX_COMPLEXITY = 100;

    /// @notice Fee dasar setiap mint, dalam wei (default 0.001 ether).
    uint256 public baseFee = 0.001 ether;

    /// @notice Fee tambahan per 1 poin kompleksitas (default 0.0001 ether).
    uint256 public feePerUnit = 0.0001 ether;

    /// @notice Pengali fee per tipe data, dalam persen (100 = 1x).
    mapping(DataType => uint256) public typeMultiplier;

    // ------------------------------------------------------------------------
    // Penyimpanan
    // ------------------------------------------------------------------------

    uint256 private _nextTokenId = 1; // tokenId berikutnya (mulai dari 1)

    mapping(uint256 => GenerativeLayer) private _layers; // tokenId => layer
    mapping(bytes32 => bool) private _usedInputHashes; // inputHash => sudah dipakai?
    mapping(address => uint256[]) private _creatorLayers; // pembuat => daftar tokenId

    // ------------------------------------------------------------------------
    // Event
    // ------------------------------------------------------------------------

    event LayerMinted(
        uint256 indexed tokenId,
        address indexed creator,
        bytes32 inputHash,
        bytes32 verificationHash,
        DataType dataType,
        uint256 complexity,
        uint256 feePaid
    );
    event MetadataUpdated(uint256 indexed tokenId, address indexed updater, string newURI);
    event FeeConfigUpdated(uint256 baseFee, uint256 feePerUnit);
    event TypeMultiplierUpdated(DataType dataType, uint256 multiplier);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------

    constructor() ERC721("GenLayer", "GLAYER") Ownable(msg.sender) {
        // Pengali default: iklim & suhu 1x, cuaca 1.2x, custom 1.5x.
        typeMultiplier[DataType.IKLIM] = 100;
        typeMultiplier[DataType.SUHU] = 100;
        typeMultiplier[DataType.CUACA] = 120;
        typeMultiplier[DataType.CUSTOM] = 150;
    }

    // ------------------------------------------------------------------------
    // Fee dinamis
    // ------------------------------------------------------------------------

    /// @notice Hitung fee mint dari tipe data + kompleksitas.
    /// @dev Rumus: baseFee + (complexity * feePerUnit * multiplier) / 100
    /// @return fee dalam wei.
    function calculateFee(DataType _dataType, uint256 _complexity) public view returns (uint256) {
        return baseFee + (_complexity * feePerUnit * typeMultiplier[_dataType]) / 100;
    }

    // ------------------------------------------------------------------------
    // Mint
    // ------------------------------------------------------------------------

    /// @notice Buat generative layer baru dari hash data eksternal.
    /// @param _inputHash keccak256 dari data eksternal mentah (tidak boleh nol
    ///        dan belum pernah dipakai — satu hash hanya bisa jadi satu layer).
    /// @param _dataType jenis data sumber (IKLIM / SUHU / CUACA / CUSTOM).
    /// @param _complexity kompleksitas layer, 1-100. Makin tinggi, makin mahal.
    /// @param _metadataURI URI metadata JSON (mis. ipfs://.../1.json).
    /// @return tokenId ID unik layer yang baru dicetak.
    function mintLayer(
        bytes32 _inputHash,
        DataType _dataType,
        uint256 _complexity,
        string calldata _metadataURI
    ) external payable nonReentrant returns (uint256) {
        // --- Validasi hash ---
        require(_inputHash != bytes32(0), "GenLayer: hash input kosong");
        require(!_usedInputHashes[_inputHash], "GenLayer: hash sudah dipakai");

        // --- Validasi kompleksitas & metadata ---
        require(
            _complexity >= MIN_COMPLEXITY && _complexity <= MAX_COMPLEXITY,
            "GenLayer: kompleksitas harus 1-100"
        );
        require(bytes(_metadataURI).length > 0, "GenLayer: metadata URI kosong");

        // --- Fee dinamis: harus dibayar, kelebihan dikembalikan ---
        uint256 fee = calculateFee(_dataType, _complexity);
        require(msg.value >= fee, "GenLayer: fee kurang");

        uint256 tokenId = _nextTokenId++;

        // Hash verifikasi: mengikat hash + pembuat + tipe + kompleksitas + ID.
        // Siapa pun bisa menghitung ulang dan membandingkannya (lihat verifyLayer).
        bytes32 verificationHash = keccak256(
            abi.encodePacked(_inputHash, msg.sender, uint8(_dataType), _complexity, tokenId)
        );

        _layers[tokenId] = GenerativeLayer({
            id: tokenId,
            creator: msg.sender,
            inputHash: _inputHash,
            verificationHash: verificationHash,
            dataType: _dataType,
            complexity: _complexity,
            metadataURI: _metadataURI,
            timestamp: block.timestamp
        });
        _usedInputHashes[_inputHash] = true;
        _creatorLayers[msg.sender].push(tokenId);

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, _metadataURI);

        // Kembalikan kelebihan bayar (kalau ada).
        if (msg.value > fee) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - fee}("");
            require(ok, "GenLayer: refund gagal");
        }

        emit LayerMinted(tokenId, msg.sender, _inputHash, verificationHash, _dataType, _complexity, fee);
        return tokenId;
    }

    // ------------------------------------------------------------------------
    // Verifikasi & baca data
    // ------------------------------------------------------------------------

    /// @notice Verifikasi layer: benar dibuat dari inputHash ini atau bukan.
    /// @dev Menghitung ulang verificationHash dari data tersimpan dan
    ///      membandingkannya dengan yang tercatat saat mint.
    /// @return true kalau hash cocok dan layer tidak pernah diubah.
    function verifyLayer(uint256 _tokenId, bytes32 _inputHash) external view returns (bool) {
        require(_ownerOf(_tokenId) != address(0), "GenLayer: layer tidak ada");
        GenerativeLayer storage layer = _layers[_tokenId];

        if (layer.inputHash != _inputHash) return false;

        bytes32 expected = keccak256(
            abi.encodePacked(
                layer.inputHash,
                layer.creator,
                uint8(layer.dataType),
                layer.complexity,
                layer.id
            )
        );
        return expected == layer.verificationHash;
    }

    /// @notice Ambil seluruh data satu layer.
    function getLayer(uint256 _tokenId) external view returns (GenerativeLayer memory) {
        require(_ownerOf(_tokenId) != address(0), "GenLayer: layer tidak ada");
        return _layers[_tokenId];
    }

    /// @notice Daftar ID layer milik satu alamat.
    function getLayersByCreator(address _creator) external view returns (uint256[] memory) {
        return _creatorLayers[_creator];
    }

    /// @notice Jumlah total layer yang sudah dicetak.
    function totalLayers() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /// @notice Cek apakah sebuah inputHash sudah dipakai untuk mint.
    function isInputHashUsed(bytes32 _inputHash) external view returns (bool) {
        return _usedInputHashes[_inputHash];
    }

    // ------------------------------------------------------------------------
    // Update metadata (pemilik layer saja)
    // ------------------------------------------------------------------------

    /// @notice Ganti metadata JSON milik layer sendiri.
    /// @dev verificationHash TIDAK berubah — metadata bukan bagian dari hash
    ///      verifikasi, jadi update metadata tidak merusak bukti asal-usul.
    function updateMetadata(uint256 _tokenId, string calldata _newURI) external {
        require(ownerOf(_tokenId) == msg.sender, "GenLayer: bukan pemilik layer");
        require(bytes(_newURI).length > 0, "GenLayer: metadata URI kosong");
        _layers[_tokenId].metadataURI = _newURI;
        _setTokenURI(_tokenId, _newURI);
        emit MetadataUpdated(_tokenId, msg.sender, _newURI);
    }

    // ------------------------------------------------------------------------
    // Admin (owner kontrak saja)
    // ------------------------------------------------------------------------

    /// @notice Ubah fee dasar.
    function setBaseFee(uint256 _newBaseFee) external onlyOwner {
        baseFee = _newBaseFee;
        emit FeeConfigUpdated(baseFee, feePerUnit);
    }

    /// @notice Ubah fee per poin kompleksitas.
    function setFeePerUnit(uint256 _newFeePerUnit) external onlyOwner {
        feePerUnit = _newFeePerUnit;
        emit FeeConfigUpdated(baseFee, feePerUnit);
    }

    /// @notice Ubah pengali fee untuk satu tipe data (dalam persen, > 0).
    function setTypeMultiplier(DataType _dataType, uint256 _multiplier) external onlyOwner {
        require(_multiplier > 0, "GenLayer: pengali harus > 0");
        typeMultiplier[_dataType] = _multiplier;
        emit TypeMultiplierUpdated(_dataType, _multiplier);
    }

    /// @notice Tarik semua fee mint yang terkumpul ke owner.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "GenLayer: tidak ada fee");
        (bool ok, ) = payable(owner()).call{value: balance}("");
        require(ok, "GenLayer: withdraw gagal");
        emit FeesWithdrawn(owner(), balance);
    }
}
