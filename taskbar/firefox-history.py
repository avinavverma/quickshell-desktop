#!/usr/bin/env python3
"""Print Firefox's most-used sites and pages as JSON, for the desktop search bar's suggestions:

    {"origins": [[host, prefix], ...], "places": [[url, title], ...]}     (most "frecent" first)

Reads the default profile's places.sqlite from a temporary copy (Firefox keeps the file open).
Nothing leaves the computer.
"""
import configparser, json, os, shutil, sqlite3, sys, tempfile

def profile_dir():
    for base in (os.path.expanduser("~/.config/mozilla/firefox"), os.path.expanduser("~/.mozilla/firefox")):
        ini = os.path.join(base, "profiles.ini")
        if not os.path.exists(ini):
            continue
        cp = configparser.ConfigParser(); cp.read(ini)
        paths = [cp[s]["Default"] for s in cp.sections() if s.startswith("Install") and "Default" in cp[s]]
        paths += [cp[s]["Path"] for s in cp.sections() if s.startswith("Profile") and cp[s].get("Default") == "1"]
        paths += [cp[s]["Path"] for s in cp.sections() if s.startswith("Profile")]
        for p in paths:
            full = p if os.path.isabs(p) else os.path.join(base, p)
            if os.path.exists(os.path.join(full, "places.sqlite")):
                return full
    return None

def main():
    prof = profile_dir()
    if not prof:
        print(json.dumps({"origins": [], "places": []})); return
    tmp = tempfile.mkdtemp()
    try:
        for name in ("places.sqlite", "places.sqlite-wal"):
            src = os.path.join(prof, name)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(tmp, name))
        db = sqlite3.connect(os.path.join(tmp, "places.sqlite"))
        origins = db.execute("SELECT host, prefix FROM moz_origins WHERE frecency > 0 "
                             "AND prefix IN ('https://', 'http://') ORDER BY frecency DESC LIMIT 1500").fetchall()
        places = db.execute("SELECT url, COALESCE(title, '') FROM moz_places WHERE hidden = 0 AND frecency > 0 "
                            "AND (url LIKE 'https://%' OR url LIKE 'http://%') ORDER BY frecency DESC LIMIT 3000").fetchall()
        print(json.dumps({"origins": origins, "places": places}))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    main()
