# Source originals

The canonical, untouched charm sources are NOT copied here. They live at:

    Design/Aurie3D/Charms/

80 `.blend` files, 57 MB, by Quaternius, licensed CC0.
Duplicating them into the library would double that for nothing, so this
folder holds `CHECKSUMS.sha256` instead — one SHA-256 per source file,
recorded at import.

Nothing in the pipeline writes to that folder. `charm_processor.py` opens
each `.blend` read-only and always saves elsewhere, so a checksum mismatch
means something outside this pipeline touched a source.

Verify at any time:

    python3 Design/Aurie3D/Scripts/charm_library.py report

Missing at import time: none
