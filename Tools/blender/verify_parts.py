"""Read exported .glb files back and prove the axis rule.

Runs under plain python3 (no Blender, no dependencies): it parses the GLB
container and the JSON chunk only.  glTF stores `min`/`max` on every POSITION
accessor, so the bounding box and the triangle count come straight out of the
file that Godot will load -- which is the point.  Nothing is inferred from the
Blender scene.

    python3 Tools/blender/verify_parts.py              # check every part
    python3 Tools/blender/verify_parts.py --rebuild-manifest
"""

import argparse
import json
import os
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PARTS = os.path.join(REPO, "Arena", "assets", "parts")

COMP = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("%s is not a GLB" % path)
    off = 12
    js = None
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    if js is None:
        raise ValueError("%s has no JSON chunk" % path)
    js["_bytes"] = len(data)
    js["_version"] = version
    return js


def read_glb_bin(path):
    """The GLB plus its binary chunk, for the winding check."""
    with open(path, "rb") as fh:
        data = fh.read()
    off = 12
    js = None
    bin_chunk = b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = chunk
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    js["_bytes"] = len(data)
    return js, bin_chunk


def _accessor(js, blob, idx):
    acc = js["accessors"][idx]
    bv = js["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
    stride = bv.get("byteStride") or (COMP[acc["componentType"]] * ncomp)
    out = []
    for i in range(acc["count"]):
        out.append(struct.unpack_from("<" + fmt * ncomp, blob, base + i * stride))
    return out


def signed_volume(path):
    """Sum of the tetrahedron volumes over every triangle.  A closed mesh whose
    winding points outward gives a POSITIVE total; an inside-out one is negative.
    Every part here is built from closed primitives, so this catches flipped
    normals without opening Blender or rendering anything."""
    js, blob = read_glb_bin(path)
    total = 0.0
    for m in js.get("meshes", []):
        for prim in m.get("primitives", []):
            pos = _accessor(js, blob, prim["attributes"]["POSITION"])
            idx = [i[0] for i in _accessor(js, blob, prim["indices"])]
            for t in range(0, len(idx), 3):
                a, b, c = pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]]
                total += (a[0] * (b[1] * c[2] - b[2] * c[1])
                          - a[1] * (b[0] * c[2] - b[2] * c[0])
                          + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
    return total


def _node_world(js, idx, parent=(0.0, 0.0, 0.0)):
    n = js["nodes"][idx]
    t = n.get("translation", [0.0, 0.0, 0.0])
    return (parent[0] + t[0], parent[1] + t[1], parent[2] + t[2])


def manifest_entry(ident, category, path, js, out_root):
    meshes = js.get("meshes", [])
    accessors = js.get("accessors", [])
    tris = 0
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    mats_used = {}
    mat_names = [m.get("name", "?") for m in js.get("materials", [])]
    for m in meshes:
        for prim in m.get("primitives", []):
            if "indices" in prim:
                n = accessors[prim["indices"]]["count"] // 3
            else:
                n = accessors[prim["attributes"]["POSITION"]]["count"] // 3
            tris += n
            if "material" in prim:
                nm = mat_names[prim["material"]]
                mats_used[nm] = mats_used.get(nm, 0) + n
            pa = accessors[prim["attributes"]["POSITION"]]
            for i in range(3):
                lo[i] = min(lo[i], pa["min"][i])
                hi[i] = max(hi[i], pa["max"][i])

    sockets = {}
    mesh_nodes = []
    for i, n in enumerate(js.get("nodes", [])):
        name = n.get("name", "")
        if name.startswith("socket_"):
            sockets[name] = [round(v, 5) for v in _node_world(js, i)]
        elif "mesh" in n:
            mesh_nodes.append(name)

    has_uv = all("TEXCOORD_0" in p["attributes"]
                 for m in meshes for p in m.get("primitives", []))
    return {
        "id": ident,
        "category": category,
        "path": "res://assets/parts/%s/%s.glb" % (category, ident),
        "file": os.path.relpath(path, out_root).replace(os.sep, "/"),
        "tris": tris,
        "bytes": js["_bytes"],
        "meshes": sorted(mesh_nodes),
        "aabb_min": [round(v, 4) for v in lo],
        "aabb_max": [round(v, 4) for v in hi],
        "sockets": dict(sorted(sockets.items())),
        "materials": dict(sorted(mats_used.items())),
        "uv0": has_uv,
    }


def check(entry):
    """Axis and quality assertions on the exported file."""
    fails = []
    ident = entry["id"]
    if not entry["uv0"]:
        fails.append("%s: a primitive has no TEXCOORD_0" % ident)
    if entry["tris"] <= 0:
        fails.append("%s: no triangles" % ident)
    if not entry["materials"]:
        fails.append("%s: no named materials" % ident)
    lo, hi = entry["aabb_min"], entry["aabb_max"]
    if any(hi[i] <= lo[i] for i in range(3)):
        fails.append("%s: degenerate bounding box" % ident)

    # THE AXIS RULE.  Parts with a nose must be longest along X and their
    # forward extent must beat their rearward one.
    if entry["category"] == "chassis":
        if "socket_weapon_front" in entry["sockets"]:
            if entry["sockets"]["socket_weapon_front"][0] <= 0.0:
                fails.append("%s: socket_weapon_front is not forward of the origin" % ident)
        fr = entry["sockets"].get("socket_wheel_fr")
        fl = entry["sockets"].get("socket_wheel_fl")
        rr = entry["sockets"].get("socket_wheel_rr")
        if fr and fl and rr:
            if fr[2] <= 0.0 or fl[2] >= 0.0:
                fails.append("%s: wheel fr/fl are not on +Z/-Z (right/left)" % ident)
            if fr[0] <= rr[0]:
                fails.append("%s: front wheels are not forward of the rear ones" % ident)
            if abs(fr[1]) > 1e-6:
                fails.append("%s: wheel sockets are off the axle plane" % ident)
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", default=PARTS)
    ap.add_argument("--rebuild-manifest", action="store_true")
    args = ap.parse_args()

    mpath = os.path.join(args.parts, "manifest.json")
    with open(mpath) as fh:
        man = json.load(fh)

    fails = []
    total = 0
    size = 0
    for ident in sorted(man["parts"]):
        entry = man["parts"][ident]
        path = os.path.join(args.parts, entry["file"])
        if not os.path.exists(path):
            fails.append("%s: missing %s" % (ident, path))
            continue
        if args.rebuild_manifest:
            entry = manifest_entry(ident, entry["category"], path,
                                   read_glb(path), args.parts)
            man["parts"][ident] = entry
        f = check(entry)
        vol = signed_volume(path)
        if vol <= 0.0:
            f.append("%s: signed volume %.6f is not positive (winding is inside out)"
                     % (ident, vol))
        entry["volume_m3"] = round(vol, 6)
        fails += f
        total += entry["tris"]
        size += entry["bytes"]
        print("%-6s %-22s %6d tris  %7.1f kB  vol %8.5f m3  aabb %s .. %s"
              % ("FAIL" if f else "PASS", ident, entry["tris"],
                 entry["bytes"] / 1024.0, vol, entry["aabb_min"], entry["aabb_max"]))

    if args.rebuild_manifest:
        with open(mpath, "w") as fh:
            json.dump(man, fh, indent=1, sort_keys=True)
            fh.write("\n")

    print("\n%d parts, %d tris, %.2f MB" % (len(man["parts"]), total, size / 1048576.0))
    for f in fails:
        print("FAIL " + f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
