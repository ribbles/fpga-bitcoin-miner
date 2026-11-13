import re
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# 1. Define Canvas Size
scale = 6
img_width, img_height = 2400, 1600
img = Image.new("RGB", (img_width, img_height), (10, 10, 12)) # Deep slate background
draw = ImageDraw.Draw(img)

# Dictionaries to track cell coordinate running sums for calculating the average (centroid)
pblock_coords = {}  # Format: { group_name: { 'sum_x': 0, 'sum_y': 0, 'count': 0 } }


def detect_target_core_count(default=1):
    """Infer CORES from known build scripts so fallback clustering matches the design."""
    build_script = Path("./build_kintex7.tcl")
    if not build_script.exists():
        return default

    try:
        for line in build_script.read_text(encoding="utf-8", errors="ignore").splitlines():
            match = re.match(r"\s*set\s+cores\s+(\d+)\s*$", line)
            if match:
                return max(1, int(match.group(1)))
    except OSError:
        pass

    return default


def kmeans(points, k, iterations=10):
    """Simple deterministic 2D k-means with x-sorted seeding (no external deps)."""
    if not points:
        return []

    unique_points = list(dict.fromkeys(points))
    if len(unique_points) <= k:
        return [tuple(map(float, p)) for p in unique_points]

    # Seed centroids by sampling across sorted x to get stable partitions per run.
    sorted_points = sorted(unique_points, key=lambda p: (p[0], p[1]))
    centroids = []
    for i in range(k):
        idx = int((i + 0.5) * len(sorted_points) / k)
        idx = min(max(idx, 0), len(sorted_points) - 1)
        centroids.append((float(sorted_points[idx][0]), float(sorted_points[idx][1])))

    for _ in range(iterations):
        sums_x = [0.0] * k
        sums_y = [0.0] * k
        counts = [0] * k

        for x, y in points:
            best_idx = 0
            best_dist = None
            for ci, (cx, cy) in enumerate(centroids):
                dx = x - cx
                dy = y - cy
                dist = dx * dx + dy * dy
                if best_dist is None or dist < best_dist:
                    best_dist = dist
                    best_idx = ci

            sums_x[best_idx] += x
            sums_y[best_idx] += y
            counts[best_idx] += 1

        moved = False
        new_centroids = []
        for ci in range(k):
            if counts[ci] == 0:
                new_centroids.append(centroids[ci])
                continue
            nx = sums_x[ci] / counts[ci]
            ny = sums_y[ci] / counts[ci]
            if abs(nx - centroids[ci][0]) > 0.25 or abs(ny - centroids[ci][1]) > 0.25:
                moved = True
            new_centroids.append((nx, ny))

        centroids = new_centroids
        if not moved:
            break

    return centroids


def nearest_centroid_key(x, y, centroids):
    best_idx = 0
    best_dist = None
    for ci, (cx, cy) in enumerate(centroids):
        dx = x - cx
        dy = y - cy
        dist = dx * dx + dy * dy
        if best_dist is None or dist < best_dist:
            best_dist = dist
            best_idx = ci
    return f"cluster_{best_idx:02d}"

# Helper function to automatically turn any Pblock name into a distinct RGB color
def get_core_color(pblock_name):
    if not pblock_name:
        return (100, 100, 100) # Muted grey for unassigned global interconnect
    hash_object = hashlib.md5(pblock_name.encode())
    hex_dig = hash_object.hexdigest()
    r = (int(hex_dig[0:2], 16) % 180) + 75
    g = (int(hex_dig[2:4], 16) % 180) + 75
    b = (int(hex_dig[4:6], 16) % 180) + 75
    return (r, g, b)

# 2. Open and parse the unfiltered text matrix first
cells = []
with open("./build_vivado/placement_dump.txt", "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if not line.strip():
            continue
        tokens = line.strip().split("|")
        if tokens[0] != "CELL" or len(tokens) <= 4:
            continue

        cell_name = tokens[1]
        cell_type = tokens[2]
        loc_string = tokens[3]
        pblock_name = tokens[4]
        loc_match = re.search(r"X(\d+)Y(\d+)", loc_string)
        if not loc_match:
            continue

        cx = int(loc_match.group(1))
        cy = int(loc_match.group(2))
        cells.append(
            {
                "name": cell_name,
                "type": cell_type,
                "cx": cx,
                "cy": cy,
                "pblock": pblock_name,
            }
        )

if cells:
    min_cx = min(c["cx"] for c in cells)
    max_cx = max(c["cx"] for c in cells)
    min_cy = min(c["cy"] for c in cells)
    max_cy = max(c["cy"] for c in cells)
else:
    min_cx = max_cx = 0
    min_cy = max_cy = 0


def infer_group_from_name(cell_name):
    # Keep explicit generate-loop core names if they survive synthesis.
    patterns = [
        r"/gg\[(\d+)\]",
        r"/core\[(\d+)\]",
        r"/core_(\d+)",
        r"/core(\d+)",
    ]
    for pattern in patterns:
        match = re.search(pattern, cell_name)
        if match:
            return f"core_{int(match.group(1)):02d}"
    return ""


has_any_pblock = any(c["pblock"] for c in cells)
has_any_name_core = any(infer_group_from_name(c["name"]) for c in cells)
centroids = []

if not has_any_pblock and not has_any_name_core:
    target_cores = detect_target_core_count(default=1)
    points = [(c["cx"], c["cy"]) for c in cells]
    centroids = kmeans(points, target_cores, iterations=12)


# Draw all placed primitives with checkerboard texture.
for cell in cells:
    cx = cell["cx"]
    cy = cell["cy"]
    px, py = cx * scale, img_height - (cy * scale)

    pblock_name = cell["pblock"]
    group_name = pblock_name or infer_group_from_name(cell["name"])
    if not group_name and centroids:
        group_name = nearest_centroid_key(cx, cy, centroids)

    if group_name:
        if group_name not in pblock_coords:
            pblock_coords[group_name] = {"sum_x": 0, "sum_y": 0, "count": 0}
        pblock_coords[group_name]["sum_x"] += px
        pblock_coords[group_name]["sum_y"] += py
        pblock_coords[group_name]["count"] += 1

    base_color = get_core_color(group_name)
    if (cx + cy) % 2 == 0:
        pixel_color = tuple(min(c + 35, 255) for c in base_color)
    else:
        pixel_color = tuple(max(c - 35, 0) for c in base_color)

    if "FF" in cell["type"] or "FD" in cell["type"]:
        pixel_color = (pixel_color[0], min(pixel_color[1] + 40, 255), pixel_color[2])

    draw.rectangle([px + 1, py + 1, px + 4, py + 4], fill=pixel_color)

# =====================================================================
# 3. TEXT ENGINE LOADING
# =====================================================================
font_paths = [
    "arial.ttf",                                              
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",  
    "/usr/share/fonts/liberation/LiberationSans-Bold.ttf"
]

font_large = None
font_small = None
for path in font_paths:
    try:
        font_large = ImageFont.truetype(path, 42)
        font_small = ImageFont.truetype(path, 28)
        break
    except IOError:
        continue

if font_large is None:
    font_large = ImageFont.load_default()
    font_small = ImageFont.load_default()

# =====================================================================
# 4. OVERLAY CORE LABELS (CALCULATED BY CENTROID / AVERAGE LOCATION)
# =====================================================================
for pb_name, data in pblock_coords.items():
    if data['count'] == 0:
        continue
        
    core_number_match = re.search(r'\d+', pb_name)
    core_label = core_number_match.group(0) if core_number_match else pb_name
    
    # Calculate the true mathematical center of all elements in this cluster
    avg_x = data['sum_x'] // data['count']
    avg_y = data['sum_y'] // data['count']
    
    try:
        left, top, right, bottom = draw.textbbox((0, 0), core_label, font=font_large)
        text_w, text_h = right - left, bottom - top
    except AttributeError:
        text_w, text_h = draw.textsize(core_label, font=font_large)
        
    # Render pure white numbers perfectly balanced over the center of the mass
    draw.text((avg_x - (text_w // 2), avg_y - (text_h // 2)), core_label, fill=(255, 255, 255), font=font_large)

# =====================================================================
# 5. DYNAMIC SUMMARY LABEL (ALL THE WAY BOTTOM LEFT, MINIMALIST WHITE)
# =====================================================================
core_count = len(pblock_coords)
summary_mode = "pblock" if has_any_pblock else ("name" if has_any_name_core else "cluster")
summary_text = f"Kintex-7 {core_count} groups ({summary_mode})"

sum_x = 20
try:
    left, top, right, bottom = draw.textbbox((0, 0), summary_text, font=font_small)
    text_h = bottom - top
except AttributeError:
    text_h = draw.textsize(summary_text, font=font_small)

sum_y = img_height - text_h - 20
draw.text((sum_x, sum_y), summary_text, fill=(255, 255, 255), font=font_small)

# 6. Output Final Master Render
if cells:
    # Crop to occupied die area and keep space for the bottom-left summary text.
    pad = 20
    left = max(0, min_cx * scale - pad)
    right = min(img_width, (max_cx * scale) + 4 + pad)
    top = max(0, img_height - (max_cy * scale) - 4 - pad)
    bottom = min(img_height, img_height - (min_cy * scale) + pad)
    bottom = max(bottom, sum_y + text_h + 20)

    if right > left and bottom > top:
        img = img.crop((left, top, right, bottom))

img.save("./build_vivado/chip_floorplan.png")
print(f"[INFO] Floorplan generated with {core_count} groups via {summary_mode} mode")
