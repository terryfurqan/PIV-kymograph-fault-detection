#!/usr/bin/env python3
"""
extract_kymograph_assets.py
===========================
Extracts full 3D spatiotemporal volumes of 2D Map-View Shortening Rate (SR)
and Velocity Gradient (VG) across all active frames for EXP 3, EXP 1, EXP 2, EXP 0,
compresses them with Zero-Run-Length Encoding (Zero-RLE), and compiles them
along with frame metadata, pusher trajectories, centerline reference images,
and benchmark Map-View fault keyframes into `fsr_autotracker_data.js`.
"""

import os
import sys
import glob
import json
import time
import base64
import multiprocessing as mp
import cv2
import numpy as np
import pandas as pd
from scipy.ndimage import median_filter, gaussian_filter

BRAIN_DIR = "/home/sandbox-main/.gemini/antigravity/brain/597e7643-6bbc-4294-857c-f2ecc6677ac7"
BASE_EXP_DIR = "/run/media/sandbox-main/BIG DATA 6TB/01_EXP_SANDBOX_MASTER/05_NEW_RUNS_2026/new_exp_OM_TERR/THRUST_Fault EXP 2026 new/Thin Skin/2 cm"
OUTPUT_DIR = "/home/sandbox-main/1. RE_XnMP"

MAP_H = 80   # Along-strike Y resolution (rows, covering Y = 30.6 .. 377.6 mm)
MAP_W = 180  # Longitudinal X resolution (cols, covering X = 0.0 .. 450.0 mm)

SR_MIN, SR_MAX = 0.008, 0.055
VG_MIN, VG_MAX = 0.008, 0.050

EXPERIMENTS = {
    "EXP_3": {
        "exp_folder": "3",
        "title": "EXP 3 (Calibrated Master — 58.5 cm Sandpack)",
        "L0_mm": 585.0,
        "dL_mm": 328.0,
        "total_strain_pct": 56.07,
        "x_max_mm": 450.0,
        "y_min_mm": 30.6,
        "y_max_mm": 377.6,
        "scale_px_per_mm": 8.5,
        "pusher_start_x_mm": 485.0,
    },
    "EXP_1": {
        "exp_folder": "1",
        "title": "EXP 1 (59.0 cm Sandpack, 33.5 cm Shortening)",
        "L0_mm": 590.0,
        "dL_mm": 335.0,
        "total_strain_pct": 56.78,
        "x_max_mm": 450.0,
        "y_min_mm": 30.6,
        "y_max_mm": 377.6,
        "scale_px_per_mm": 8.5,
        "pusher_start_x_mm": 485.0,
    },
    "EXP_2": {
        "exp_folder": "2",
        "title": "EXP 2 (50.0 cm Sandpack, 20.0 cm Shortening)",
        "L0_mm": 500.0,
        "dL_mm": 200.0,
        "total_strain_pct": 40.00,
        "x_max_mm": 450.0,
        "y_min_mm": 30.6,
        "y_max_mm": 377.6,
        "scale_px_per_mm": 8.5,
        "pusher_start_x_mm": 485.0,
    },
    "EXP_0": {
        "exp_folder": "0",
        "title": "EXP 0 (69.6 cm Sandpack, 35.0 cm Shortening)",
        "L0_mm": 696.0,
        "dL_mm": 350.0,
        "total_strain_pct": 50.29,
        "x_max_mm": 450.0,
        "y_min_mm": 30.6,
        "y_max_mm": 377.6,
        "scale_px_per_mm": 8.5,
        "pusher_start_x_mm": 485.0,
    }
}

DUAL_CROPS = {
    "EXP_0": {"y": (277, 2205), "sr_x": (178, 3178), "vg_x": (3332, 6328)},
    "EXP_1": {"y": (277, 2205), "sr_x": (178, 3207), "vg_x": (3303, 6328)},
    "EXP_2": {"y": (277, 2205), "sr_x": (178, 3207), "vg_x": (3303, 6328)},
    "EXP_3": {"y": (277, 2205), "sr_x": (178, 3207), "vg_x": (3303, 6328)},
}


def encode_zero_rle(arr_u8):
    """Compresses a sparse uint8 array using Zero-Run-Length Encoding and Base64."""
    flat = arr_u8.ravel()
    out = bytearray()
    n = len(flat)
    nz_idx = np.flatnonzero(flat)
    if len(nz_idx) == 0:
        while n > 0:
            step = min(255, n)
            out.append(0)
            out.append(step)
            n -= step
        return base64.b64encode(out).decode("ascii")

    prev = 0
    for idx in nz_idx:
        zeros = int(idx - prev)
        while zeros > 0:
            step = min(255, zeros)
            out.append(0)
            out.append(step)
            zeros -= step
        out.append(int(flat[idx]))
        prev = idx + 1

    tail = int(n - prev)
    while tail > 0:
        step = min(255, tail)
        out.append(0)
        out.append(step)
        tail -= step
    return base64.b64encode(out).decode("ascii")


def encode_image_base64(img_bgr, quality=82, max_dim=900):
    h, w = img_bgr.shape[:2]
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        img_bgr = cv2.resize(img_bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    success, buf = cv2.imencode(".jpg", img_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
    return f"data:image/jpeg;base64,{base64.b64encode(buf).decode('ascii')}"


def _worker_process_frame(args):
    """Worker to compute 2D Map-View SR and VG for a single PIV frame."""
    npz_path, pusher_x_mm, scale_px_per_mm, x_max_mm = args
    try:
        d = np.load(npz_path, allow_pickle=True)
        u = d["u"]
        vel = d["vel_mag"]
    except Exception:
        return (
            np.zeros((MAP_H, MAP_W), dtype=np.uint8),
            np.zeros((MAP_H, MAP_W), dtype=np.uint8),
            0.0,
            0.0,
            0.0
        )

    n_rows, n_cols = u.shape
    r_start = 25
    r_end = min(321, n_rows - 20)

    # Denoise
    u_dn = gaussian_filter(median_filter(u, size=5, mode="reflect"), sigma=3.5)
    vel_dn = gaussian_filter(median_filter(vel, size=5, mode="reflect"), sigma=3.5)

    sr = np.maximum(0.0, -np.gradient(u_dn, 10.0, axis=1))
    vg = np.abs(np.gradient(vel_dn, 10.0, axis=1))

    # Crop to active sandpack Y rows and X <= 450 mm
    max_col = min(n_cols, int(round((x_max_mm * scale_px_per_mm) / 10.0)) + 1)
    sr_sub = sr[r_start:r_end, :max_col]
    vg_sub = vg[r_start:r_end, :max_col]

    # Mask pusher plate edge
    x_cols_mm = (np.arange(max_col) * 10.0) / scale_px_per_mm
    mask_sand = x_cols_mm < (pusher_x_mm - 2.0)
    sr_sub = np.where(mask_sand[None, :], sr_sub, 0.0)
    vg_sub = np.where(mask_sand[None, :], vg_sub, 0.0)

    # Resize to (MAP_H, MAP_W) where row 0 = y_min_mm and row MAP_H-1 = y_max_mm
    sr_res = cv2.resize(sr_sub.astype(np.float32), (MAP_W, MAP_H), interpolation=cv2.INTER_AREA)
    vg_res = cv2.resize(vg_sub.astype(np.float32), (MAP_W, MAP_H), interpolation=cv2.INTER_AREA)

    # Activity metrics for sparkline
    peak_sr = float(np.percentile(sr_res, 99.2)) if sr_res.size > 0 else 0.0
    peak_vg = float(np.percentile(vg_res, 99.2)) if vg_res.size > 0 else 0.0
    row_max_sr = np.max(sr_res, axis=1)
    active_pct = float(np.mean(row_max_sr >= 0.020) * 100.0)

    # Quantize to uint8 (0 = below baseline, 1..255 = [MIN, MAX])
    sr_u8 = np.where(
        sr_res < SR_MIN,
        0,
        np.clip(1 + ((sr_res - SR_MIN) / (SR_MAX - SR_MIN)) * 254.0, 1, 255)
    ).round().astype(np.uint8)

    vg_u8 = np.where(
        vg_res < VG_MIN,
        0,
        np.clip(1 + ((vg_res - VG_MIN) / (VG_MAX - VG_MIN)) * 254.0, 1, 255)
    ).round().astype(np.uint8)

    return sr_u8, vg_u8, round(peak_sr, 4), round(peak_vg, 4), round(active_pct, 1)


def auto_trace_ridge_on_map(mat_2d_u8, x_corridor_mm, x_max_mm, y_min_mm, y_max_mm, thresh_u8):
    """Traces the fault ridge X(Y) across rows of a 2D Map-View frame within x_corridor_mm."""
    c_min = max(1, int(round((x_corridor_mm[0] / x_max_mm) * (MAP_W - 1))))
    c_max = min(MAP_W - 2, int(round((x_corridor_mm[1] / x_max_mm) * (MAP_W - 1))))
    if c_min >= c_max:
        c_min, c_max = 1, MAP_W - 2

    pts = []
    for r in range(0, MAP_H, 2):
        row_slice = mat_2d_u8[r, c_min:c_max + 1]
        max_v = int(np.max(row_slice))
        if max_v >= thresh_u8:
            best_c = c_min + int(np.argmax(row_slice))
            x_mm = (best_c / (MAP_W - 1)) * x_max_mm
            y_mm = y_min_mm + (r / (MAP_H - 1)) * (y_max_mm - y_min_mm)
            pts.append([round(float(x_mm), 1), round(float(y_mm), 1)])
    return pts


def build_default_faults_for_exp(exp_id, photo_frames, strains, sr_vol, exp_meta, df_bench):
    """Creates initial fault catalog with Map-View keyframes (onset, growth, breach)."""
    fault_colors = ["#ef4444", "#3b82f6", "#10b981", "#a855f7", "#f97316", "#eab308", "#ec4899", "#14b8a6"]
    thresh_u8 = int(1 + ((0.020 - SR_MIN) / (SR_MAX - SR_MIN)) * 254.0)

    def find_act_idx_by_photo(p_target):
        diffs = [abs(p - p_target) for p in photo_frames]
        return int(np.argmin(diffs))

    faults = []
    if exp_id == "EXP_3":
        # User-taught & calibrated domain keyframes for EXP 3
        exp3_specs = [
            {
                "id": "F1", "name": "Thrust Fault 1 (F1)", "color": "#ef4444", "corridor": (380, 425),
                "moments": [
                    {"stage": "onset",  "label": "Nucleation Onset (Frame 22)", "photo_frame": 22},
                    {"stage": "breach", "label": "Full Breach (Frame 26)",      "photo_frame": 26},
                ]
            },
            {
                "id": "F2", "name": "Thrust Fault 2 (F2)", "color": "#3b82f6", "corridor": (350, 395),
                "moments": [
                    {"stage": "onset",  "label": "Early Nucleation (Frame 40)", "photo_frame": 40},
                    {"stage": "growth", "label": "Lower Segment Y=0-275 (Frame 44)", "photo_frame": 44},
                    {"stage": "breach", "label": "Upper Segment & Breach (Frame 55)", "photo_frame": 55},
                ]
            },
            {
                "id": "F3", "name": "Thrust Fault 3 (F3)", "color": "#10b981", "corridor": (280, 328),
                "moments": [
                    {"stage": "onset",  "label": "Nucleation X=300, Y=325 (Frame 77)", "photo_frame": 77},
                    {"stage": "breach", "label": "Peak Development (Frame 87)",        "photo_frame": 87},
                ]
            },
            {
                "id": "F4", "name": "Thrust Fault 4 (F4)", "color": "#a855f7", "corridor": (205, 248),
                "moments": [
                    {"stage": "onset",  "label": "First Nucleation X=230 (Frame 128)", "photo_frame": 128},
                    {"stage": "growth", "label": "Early Growth Stage (Frame 134)",     "photo_frame": 134},
                    {"stage": "breach", "label": "Full Wall-to-Wall Breach (Frame 149)", "photo_frame": 149},
                ]
            },
            {
                "id": "F5", "name": "Thrust Fault 5 (F5)", "color": "#f97316", "corridor": (140, 185),
                "moments": [
                    {"stage": "onset",  "label": "Nucleation X=160, Y=75-200 (Frame 172)", "photo_frame": 172},
                    {"stage": "growth", "label": "Early Development (Frame 186)",          "photo_frame": 186},
                    {"stage": "breach", "label": "Full Through-Going Breach (Frame 206)",  "photo_frame": 206},
                ]
            },
            {
                "id": "F6", "name": "Thrust Fault 6 (F6)", "color": "#eab308", "corridor": (75, 120),
                "moments": [
                    {"stage": "onset",  "label": "Nucleation Onset (Frame 226)", "photo_frame": 226},
                    {"stage": "breach", "label": "Full Breach (Frame 258)",      "photo_frame": 258},
                ]
            },
            {
                "id": "F7", "name": "Thrust Fault 7 (F7)", "color": "#ec4899", "corridor": (45, 88),
                "moments": [
                    {"stage": "onset",  "label": "Nucleation Onset (Frame 255)", "photo_frame": 255},
                    {"stage": "breach", "label": "Full Breach (Frame 288)",      "photo_frame": 288},
                ]
            },
            {
                "id": "F8", "name": "Thrust Fault 8 (F8)", "color": "#14b8a6", "corridor": (20, 65),
                "moments": [
                    {"stage": "onset",  "label": "Nucleation Onset (Frame 290)", "photo_frame": 290},
                    {"stage": "breach", "label": "Full Breach (Frame 308)",      "photo_frame": 308},
                ]
            },
        ]
        for sp in exp3_specs:
            keyframes = []
            for m in sp["moments"]:
                act_idx = find_act_idx_by_photo(m["photo_frame"])
                pts = auto_trace_ridge_on_map(
                    sr_vol[act_idx], sp["corridor"],
                    exp_meta["x_max_mm"], exp_meta["y_min_mm"], exp_meta["y_max_mm"], thresh_u8
                )
                if not pts:
                    x_mid = 0.5 * (sp["corridor"][0] + sp["corridor"][1])
                    pts = [[round(x_mid, 1), 120.0], [round(x_mid, 1), 280.0]]
                keyframes.append({
                    "stage": m["stage"],
                    "label": m["label"],
                    "active_frame": act_idx,
                    "photo_frame": int(photo_frames[act_idx]),
                    "strain_pct": round(float(strains[act_idx]), 2),
                    "pts": pts
                })
            faults.append({
                "id": sp["id"],
                "name": sp["name"],
                "color": sp["color"],
                "visible": True,
                "locked": False,
                "corridor": list(sp["corridor"]),
                "keyframes": keyframes
            })
    else:
        # Build from comparative CSV for EXP_0, EXP_1, EXP_2
        sub = df_bench[df_bench["experiment_id"] == exp_id] if df_bench is not None else []
        for idx, (_, r) in enumerate(sub.iterrows()):
            fid = str(r["fault_id"])
            p_nuc = int(r["nucleation_frame_raw"])
            p_full = int(r["full_rupture_frame_raw"])
            act_nuc = find_act_idx_by_photo(p_nuc)
            act_full = find_act_idx_by_photo(p_full)
            # Estimate corridor from progressive position
            x_center = max(35.0, 410.0 - idx * 50.0)
            corr = (max(10.0, x_center - 35.0), min(445.0, x_center + 35.0))
            pts_nuc = auto_trace_ridge_on_map(
                sr_vol[act_nuc], corr, exp_meta["x_max_mm"], exp_meta["y_min_mm"], exp_meta["y_max_mm"], thresh_u8
            ) or [[round(x_center, 1), 180.0], [round(x_center, 1), 240.0]]
            pts_full = auto_trace_ridge_on_map(
                sr_vol[act_full], corr, exp_meta["x_max_mm"], exp_meta["y_min_mm"], exp_meta["y_max_mm"], thresh_u8
            ) or [[round(x_center, 1), 40.0], [round(x_center, 1), 360.0]]

            faults.append({
                "id": fid,
                "name": str(r["fault_name"]),
                "color": fault_colors[idx % len(fault_colors)],
                "visible": True,
                "locked": False,
                "corridor": [round(corr[0], 1), round(corr[1], 1)],
                "keyframes": [
                    {
                        "stage": "onset",
                        "label": f"Nucleation Onset (Frame {int(photo_frames[act_nuc])})",
                        "active_frame": act_nuc,
                        "photo_frame": int(photo_frames[act_nuc]),
                        "strain_pct": round(float(strains[act_nuc]), 2),
                        "pts": pts_nuc
                    },
                    {
                        "stage": "breach",
                        "label": f"Full Breach (Frame {int(photo_frames[act_full])})",
                        "active_frame": act_full,
                        "photo_frame": int(photo_frames[act_full]),
                        "strain_pct": round(float(strains[act_full]), 2),
                        "pts": pts_full
                    }
                ]
            })
    return faults


def process_experiment(exp_id, exp_meta, df_bench, pool):
    t0 = time.time()
    exp_root = os.path.join(BASE_EXP_DIR, exp_meta["exp_folder"])
    piv_dir = os.path.join(exp_root, "OUTPUT", "PIV", "M")
    manifest_csv = os.path.join(piv_dir, "manifest.csv")
    strain_cands = glob.glob(os.path.join(exp_root, "EXP_metadata", "*strain*.csv"))

    df_manifest = None
    if os.path.exists(manifest_csv):
        try:
            df_manifest = pd.read_csv(manifest_csv)
            if "pair_idx" not in df_manifest.columns:
                df_manifest = None
        except Exception:
            df_manifest = None
    if df_manifest is None and strain_cands:
        df_manifest = pd.read_csv(strain_cands[0])

    # Filter dead & motor stall frames (same V2.4 protocol)
    dead_idx = set(df_manifest[df_manifest["is_dead_kymo"]].index) if "is_dead_kymo" in df_manifest.columns else set()
    stall_idx = set(df_manifest[(df_manifest["pair_idx"] > 90) & (df_manifest["mean_vel_px"] < 0.6)].index) if "mean_vel_px" in df_manifest.columns else set()
    excluded = dead_idx.union(stall_idx)
    active_indices = [i for i in range(len(df_manifest)) if i not in excluded]

    n_active = len(active_indices)
    photo_frames = [int(df_manifest.iloc[i]["pair_idx"]) if "pair_idx" in df_manifest.columns else int(i) for i in active_indices]

    # Strain array
    if strain_cands:
        df_st = pd.read_csv(strain_cands[0])
        if "cumulative_strain_pct" in df_st.columns and len(df_st) == len(df_manifest):
            strains = [round(float(df_st.iloc[i]["cumulative_strain_pct"]), 3) for i in active_indices]
        else:
            strains = [round((k / max(1, n_active - 1)) * exp_meta["total_strain_pct"], 3) for k in range(n_active)]
    else:
        strains = [round((k / max(1, n_active - 1)) * exp_meta["total_strain_pct"], 3) for k in range(n_active)]

    L0_mm = exp_meta["L0_mm"]
    disps_mm = [round((s / 100.0) * L0_mm, 2) for s in strains]
    times_min = [round((k * 22.0) / 60.0, 2) for k in range(n_active)]
    pusher_xs_mm = [round(max(20.0, exp_meta["pusher_start_x_mm"] - d), 1) for d in disps_mm]

    # Build worker tasks for all active frames
    tasks = []
    for k, act_i in enumerate(active_indices):
        npz_name = df_manifest.iloc[act_i]["npz_file"]
        npz_path = os.path.join(piv_dir, "npz", npz_name)
        tasks.append((npz_path, pusher_xs_mm[k], exp_meta["scale_px_per_mm"], exp_meta["x_max_mm"]))

    results = pool.map(_worker_process_frame, tasks)

    sr_vol = np.stack([r[0] for r in results], axis=0)  # (N, MAP_H, MAP_W)
    vg_vol = np.stack([r[1] for r in results], axis=0)
    peak_srs = [r[2] for r in results]
    peak_vgs = [r[3] for r in results]
    active_pcts = [r[4] for r in results]

    sr_rle_b64 = encode_zero_rle(sr_vol)
    vg_rle_b64 = encode_zero_rle(vg_vol)

    # Extract centerline reference kymograph image
    exp_code = exp_id.replace("_", "")
    dual_path = os.path.join(BRAIN_DIR, f"Figure_Kymograph_Centerline_Dual_SR_VG_{exp_code}.png")
    kymo_sr_b64 = None
    kymo_vg_b64 = None
    if os.path.exists(dual_path):
        img_dual = cv2.imread(dual_path)
        c = DUAL_CROPS[exp_id]
        y1, y2 = c["y"]
        kymo_sr_b64 = encode_image_base64(img_dual[y1:y2, c["sr_x"][0]:c["sr_x"][1]], quality=80, max_dim=700)
        kymo_vg_b64 = encode_image_base64(img_dual[y1:y2, c["vg_x"][0]:c["vg_x"][1]], quality=80, max_dim=700)

    default_faults = build_default_faults_for_exp(exp_id, photo_frames, strains, sr_vol, exp_meta, df_bench)

    el = time.time() - t0
    print(f"  ✓ {exp_id}: {n_active} active frames ({MAP_W}x{MAP_H}), SR RLE={len(sr_rle_b64)/1024:.1f} KB, VG RLE={len(vg_rle_b64)/1024:.1f} KB ({el:.1f}s)")

    out = dict(exp_meta)
    out.update({
        "id": exp_id,
        "active_frames": n_active,
        "map_w": MAP_W,
        "map_h": MAP_H,
        "sr_range": [SR_MIN, SR_MAX],
        "vg_range": [VG_MIN, VG_MAX],
        "calibrated_threshold": 0.020,
        "photo_frames": photo_frames,
        "strains": strains,
        "disps_mm": disps_mm,
        "times_min": times_min,
        "pusher_xs_mm": pusher_xs_mm,
        "peak_srs": peak_srs,
        "peak_vgs": peak_vgs,
        "active_pcts": active_pcts,
        "map_sr_rle_b64": sr_rle_b64,
        "map_vg_rle_b64": vg_rle_b64,
        "kymo_sr_image_url": kymo_sr_b64,
        "kymo_vg_image_url": kymo_vg_b64,
        "default_faults": default_faults,
    })
    return out


def main():
    print("=" * 75)
    print("Extracting 3D Spatiotemporal Map-View Volumes (SR & VG) Across All Exps")
    print("=" * 75)

    csv_path = os.path.join(BRAIN_DIR, "MASTER_COMPARATIVE_KINEMATICS_THIN_SKIN_2CM.csv")
    df_bench = pd.read_csv(csv_path) if os.path.exists(csv_path) else None

    manifest_data = {}
    n_workers = min(16, os.cpu_count() or 8)
    with mp.Pool(processes=n_workers) as pool:
        for exp_id in ["EXP_3", "EXP_1", "EXP_2", "EXP_0"]:
            print(f"Processing {exp_id}...")
            manifest_data[exp_id] = process_experiment(exp_id, EXPERIMENTS[exp_id], df_bench, pool)

    js_output_path = os.path.join(OUTPUT_DIR, "fsr_autotracker_data.js")
    with open(js_output_path, "w", encoding="utf-8") as f:
        f.write("/**\n")
        f.write(" * fsr_autotracker_data.js\n")
        f.write(" * Pre-bundled 3D Spatiotemporal 2D Map-View (X vs Y) datasets for GRAIN 2.1\n")
        f.write(" * Contains Zero-RLE compressed SR and VG Map-View volumes across all frames.\n")
        f.write(" */\n\n")
        f.write("window.FSR_EXPERIMENTS = ")
        json.dump(manifest_data, f, separators=(",", ":"))
        f.write(";\n")

    size_kb = os.path.getsize(js_output_path) / 1024.0
    print("=" * 75)
    print(f"✓ Generated {js_output_path} ({size_kb:.1f} KB total for all 4 experiments!)")
    print("=" * 75)


if __name__ == "__main__":
    main()
