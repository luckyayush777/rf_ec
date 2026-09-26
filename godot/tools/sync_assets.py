"""Copy Blender exports and extract Godot part metadata. No third-party packages required."""
import hashlib
import json
from pathlib import Path
import shutil
import struct

REPO = Path(__file__).resolve().parents[2]
ASSETS = REPO / 'godot/assets'


def main():
    sources = ['models/gpu.glb', 'models/repair-shop.glb', 'models/shop-interior.glb']
    # Audio is authored directly in Godot; retain its hashes in the manifest.
    audio = ['godot/assets/manual-screwdriver.wav', 'godot/assets/cleaning-complete.ogg']
    hashes = {}
    ASSETS.mkdir(parents=True, exist_ok=True)
    for source in sources + audio:
        path = REPO / source
        hashes[source] = hashlib.sha256(path.read_bytes()).hexdigest()
        if source in sources:
            shutil.copyfile(path, ASSETS / path.name)
    gpu = (ASSETS / 'gpu.glb').read_bytes()
    if gpu[:4] != b'glTF' or gpu[16:20] != b'JSON':
        raise ValueError('Expected binary glTF with a JSON first chunk')
    length = struct.unpack_from('<I', gpu, 12)[0]
    document = json.loads(gpu[20:20 + length])
    nodes = document['nodes']
    parents = {child: index for index, node in enumerate(nodes) for child in node.get('children', [])}
    parts = []
    for index, node in enumerate(nodes):
        encoded = node.get('extras', {}).get('bench_part')
        if not encoded:
            continue
        metadata = json.loads(encoded)
        parent = nodes[parents[index]].get('name', '') if index in parents else ''
        parts.append({'id': node['name'], 'parent': parent, **metadata})
    manifest = {'sources': hashes, 'parts': parts}
    (ASSETS / 'gpu-parts.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'Synced {len(sources)} models and {len(parts)} named part definitions.')


if __name__ == '__main__':
    main()
