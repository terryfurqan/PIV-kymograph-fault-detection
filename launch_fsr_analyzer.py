#!/usr/bin/env python3
"""
launch_fsr_analyzer.py
======================
Launcher & Dedicated Local Server for GRAIN 2.1 FSR Analyzer
Serves the application at http://localhost:8089/FSR_Analyzer.html
Handles saving interpretation JSON and kinematics CSV directly to disk.
"""

import os
import sys
import json
import argparse
import webbrowser
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = 8089
WORKSPACE_DIR = Path(__file__).resolve().parent

class FSRAnalyzerRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WORKSPACE_DIR), **kwargs)

    def do_POST(self):
        if self.path == "/api/save_picks":
            content_length = int(self.headers.get("Content-Length", 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode("utf-8"))
                exp_id = data.get("experiment_id", "EXP_3")
                out_path = WORKSPACE_DIR / f"FSR_Interpreted_Picks_{exp_id}.json"
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
                
                print(f"\n💾 [API] Saved interpretation picks to: {out_path}")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok", "path": str(out_path)}).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "error", "message": str(e)}).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

def run_server(port=PORT, open_browser=True):
    print("=" * 75)
    print("⚡ GRAIN 2.1 — FSR ANALYZER (MAP-VIEW FAULT HORIZON AUTO-TRACKER)")
    print("=" * 75)
    print(f"🌐 Server URL : http://localhost:{port}/FSR_Analyzer.html")
    print(f"📁 Workspace  : {WORKSPACE_DIR}")
    print(f"💡 Offline    : file://{WORKSPACE_DIR / 'FSR_Analyzer.html'}")
    print("=" * 75)

    server = HTTPServer(("127.0.0.1", port), FSRAnalyzerRequestHandler)
    if open_browser:
        try:
            webbrowser.open(f"http://localhost:{port}/FSR_Analyzer.html")
        except Exception:
            pass

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping FSR Analyzer server...")
        server.server_close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Launch FSR Analyzer local server")
    parser.add_argument("--port", "-p", type=int, default=PORT, help="Port to run server on")
    parser.add_argument("--no-browser", action="store_true", help="Do not open browser automatically")
    args = parser.parse_args()

    run_server(port=args.port, open_browser=not args.no_browser)
