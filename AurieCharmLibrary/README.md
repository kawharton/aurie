# Aurie Charm Library

Durable home for the charm assets. It sits outside `Auries/Assets.xcassets`
on purpose: the asset catalog holds only what a build ships, and this holds
everything the charms are *made of* — provenance, licences, processed
masters, previews and the record of how each one was made.

Nothing in here is wired into the iOS app yet.

## Layout

| folder | holds |
| --- | --- |
| `_SOURCE_ORIGINALS/` | a pointer to the untouched downloads plus a SHA-256 for each |
| `_SOURCE_LICENSES/` | the licence/readme files that came with them, kept permanently |
| `_MANIFESTS/charms.json` | the single machine-readable index of every charm |
| `_PROCESSED/` | `<charm_id>.blend` — the processed Aurie masters |
| `_THUMBNAILS/` | `<charm_id>.png` — transparent previews, one camera for all |
| `animals/` `food/` `nature/` `magic/` `objects/` `adventure/` `vehicles/` `characters/` | `<charm_id>.json` — the per-charm processing record |

Machine-addressed outputs are flat so a build step can find them by id;
the human-readable record is filed by category, because browsing for a
charm is something people do by category. No file is stored twice.

## The originals are not copied here

The 73 source `.blend` files stay at `Design/Aurie3D/Charms/`. Copying
53 MB into the library would buy nothing, so `_SOURCE_ORIGINALS/` holds
`CHECKSUMS.sha256` instead. The processor re-hashes every source after it
runs and aborts if one changed, so "we never modified the originals" is a
checkable fact rather than a claim.

## Commands

```sh
# structure, provenance, checksums, manifest (safe to re-run)
python3 Design/Aurie3D/Scripts/charm_library.py init

# what is in the library, and re-verify every source hash
python3 Design/Aurie3D/Scripts/charm_library.py report

# process charms (pilot batch, or --ids a,b,c)
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/charm_processor.py -- --pilot

# the two review sheets
python3 Design/Aurie3D/Scripts/charm_contact_sheet.py --source-dir <dir>
```

## Provenance

Every model is by **Quaternius**, licensed **CC0 1.0** — see
`_SOURCE_LICENSES/`. CC0 imposes no attribution requirement, but creator,
pack and origin are tracked anyway so the library can always answer where
an asset came from. Where the download does not state something (pack
name, per-model URL) the manifest stores `UNKNOWN` rather than a guess.
