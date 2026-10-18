#!/usr/bin/env python3
"""
prepare_resized_photos.py
=========================
Generates lightweight, resized background photo frames for FSR Analyzer.
Extracts and crops each active frame to the exact physical sandbox area:
  X in [0, 450 mm] -> cols [0:3825]
  Y in [30.6, 377.6 mm] -> rows [250:3210]
Resizes to 960x743 px JPEG (quality 78) so each file is only ~45-100 KB.
Supports EXP_3, EXP_2, EXP_1, and EXP_0.
"""

import os
import sys
import time
from pathlib import Path
import cv2
import numpy as np
import pandas as pd
from concurrent.futures import ProcessPoolExecutor

WORKSPACE_DIR = Path("/home/sandbox-main/1. RE_XnMP")
BASE_EXP_DIR = Path("/run/media/sandbox-main/BIG DATA 6TB/01_EXP_SANDBOX_MASTER/05_NEW_RUNS_2026/new_exp_OM_TERR/THRUST_Fault EXP 2026 new/Thin Skin/2 cm")
RAW_M_DIR = Path("/run/media/sandbox-main/BIG DATA 6TB/01_EXP_SANDBOX_MASTER/05_NEW_RUNS_2026/new_exp_OM_TERR/M/2 cm")
OUT_BASE = WORKSPACE_DIR / "assets" / "resized_photos"

TARGET_W = 960
TARGET_H = 743

def process_cropped_frame(args):
    in_path, out_path, y1, y2, x1, x2 = args
    if not os.path.exists(in_path):
        return False
    im = cv2.imread(in_path)
    if im is None:
        return False
    roi = im[y1:y2, x1:x2]
    res = cv2.resize(roi, (TARGET_W, TARGET_H), interpolation=cv2.INTER_AREA)
    cv2.imwrite(str(out_path), res, [int(cv2.IMWRITE_JPEG_QUALITY), 78])
    return True

def process_raw_with_rotation(args):
    in_path, out_path, rot_deg, crop_x, crop_y, crop_w, crop_h, y1, y2, x1, x2 = args
    if not os.path.exists(in_path):
        return False
    im = cv2.imread(in_path)
    if im is None:
        return False
    
    h, w = im.shape[:2]
    center = (w / 2.0, h / 2.0)
    M = cv2.getRotationMatrix2D(center, rot_deg, 1.0)
    cos = np.abs(M[0, 0])
    sin = np.abs(M[0, 1])
    nW = int((h * sin) + (w * cos))
    nH = int((h * cos) + (w * sin))
    M[0, 2] += (nW / 2) - center[0]
    M[1, 2] += (nH / 2) - center[1]
    rot = cv2.warpAffine(im, M, (nW, nH))
    
    # Primary crop
    crop = rot[crop_y:crop_y + crop_h, crop_x:crop_x + crop_w]
    # Active sandbox crop
    roi = crop[y1:y2, x1:x2]
    res = cv2.resize(roi, (TARGET_W, TARGET_H), interpolation=cv2.INTER_AREA)
    cv2.imwrite(str(out_path), res, [int(cv2.IMWRITE_JPEG_QUALITY), 78])
    return True

def process_exp_3():
    exp_id = "EXP_3"
    print(f"=== Processing {exp_id} ===")
    exp_dir = BASE_EXP_DIR / "3"
    raw_crop_dir = exp_dir / "RAW_CROP" / "M"
    manifest_p = exp_dir / "OUTPUT" / "PIV" / "M" / "manifest.csv"
    
    if not manifest_p.exists():
        print(f"Manifest not found: {manifest_p}")
        return
        
    df = pd.read_csv(manifest_p)
    dead_idx = set(df[df['is_dead_kymo']].index) if 'is_dead_kymo' in df.columns else set()
    stall_idx = set(df[(df['pair_idx'] > 90) & (df['mean_vel_px'] < 0.6)].index) if 'mean_vel_px' in df.columns else set()
    excluded = dead_idx.union(stall_idx)
    active_indices = [i for i in range(len(df)) if i not in excluded]

    out_dir = OUT_BASE / exp_id
    out_dir.mkdir(parents=True, exist_ok=True)

    tasks = []
    for k, act_i in enumerate(active_indices):
        out_p = str(out_dir / f"frame_{k:04d}.jpg")
        if os.path.exists(out_p):
            continue
        img_name = df.iloc[act_i]['frame_b']
        in_p = str(raw_crop_dir / img_name)
        tasks.append((in_p, out_p, 250, 3210, 0, 3825))

    if tasks:
        print(f"Running {len(tasks)} frame resizes on 16 workers...")
        t0 = time.time()
        with ProcessPoolExecutor(max_workers=16) as pool:
            results = list(pool.map(process_cropped_frame, tasks))
        el = time.time() - t0
        print(f"✓ {exp_id}: Done {sum(results)}/{len(tasks)} frames in {el:.2f}s")
    else:
        print(f"✓ {exp_id}: All {len(active_indices)} frames already exist!")

def process_exp_unstitched(exp_id, folder_name):
    print(f"=== Processing {exp_id} ===")
    exp_dir = BASE_EXP_DIR / folder_name
    raw_cam_dir = RAW_M_DIR / folder_name
    manifest_p = exp_dir / "OUTPUT" / "PIV" / "M" / "manifest.csv"
    
    if not manifest_p.exists():
        print(f"Manifest not found: {manifest_p}")
        return
        
    df = pd.read_csv(manifest_p)
    dead_idx = set(df[df['is_dead_kymo']].index) if 'is_dead_kymo' in df.columns else set()
    stall_idx = set(df[(df['pair_idx'] > 90) & (df['mean_vel_px'] < 0.6)].index) if 'mean_vel_px' in df.columns else set()
    excluded = dead_idx.union(stall_idx)
    active_indices = [i for i in range(len(df)) if i not in excluded]

    out_dir = OUT_BASE / exp_id
    out_dir.mkdir(parents=True, exist_ok=True)

    tasks = []
    for k, act_i in enumerate(active_indices):
        out_p = str(out_dir / f"frame_{k:04d}.jpg")
        if os.path.exists(out_p):
            continue
        # Map frame_b name like M_2cm_2_IMG_5290.jpg to raw camera filename IMG_5290.JPG
        m_name = df.iloc[act_i]['frame_b']
        parts = m_name.split("_")
        cam_num = parts[-1].replace(".jpg", "").replace(".JPG", "")
        cam_name = f"IMG_{cam_num}.JPG"
        in_p = str(raw_cam_dir / cam_name)
        if not os.path.exists(in_p):
            in_p = str(raw_cam_dir / f"IMG_{cam_num}.jpg")
            
        tasks.append((in_p, out_p, -2.0, 330, 570, 4048, 3470, 250, 3210, 0, 3825))

    if tasks:
        print(f"Running {len(tasks)} frame rotations & resizes on 16 workers...")
        t0 = time.time()
        with ProcessPoolExecutor(max_workers=16) as pool:
            results = list(pool.map(process_raw_with_rotation, tasks))
        el = time.time() - t0
        print(f"✓ {exp_id}: Done {sum(results)}/{len(tasks)} frames in {el:.2f}s")
    else:
        print(f"✓ {exp_id}: All {len(active_indices)} frames already exist!")

if __name__ == "__main__":
    process_exp_3()
    process_exp_unstitched("EXP_2", "2")
    process_exp_unstitched("EXP_1", "1")
    process_exp_unstitched("EXP_0", "0")
