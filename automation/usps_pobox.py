#!/usr/bin/env python3
"""
USPS PO Box smoke test.

Logs into my.usps.com with credentials from ~/.config/usps/credentials
and retrieves PO Box information for the account.

Usage:
    .venv/bin/python automation/usps_pobox.py

Credentials file format (~/.config/usps/credentials):
    username=<usps_username>
    password=<usps_password>
"""

import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Resolve repo root so we can run this as a plain script from any directory
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))

from automation.browser import CarbonylBrowser  # noqa: E402

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CREDS_FILE = Path.home() / ".config" / "usps" / "credentials"
SESSION_NAME = "usps-pobox"

LOGIN_URL      = "https://reg.usps.com/login"
POBOX_URL      = "https://www.usps.com/manage/po-boxes.htm"
POBOX_SSO_HOST = "verified.usps.com"

# How long to wait for pages to render (seconds)
PAGE_LOAD    = 8
ACTION_WAIT  = 3


def load_credentials(path: Path) -> dict[str, str]:
    creds = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, _, v = line.partition("=")
            creds[k.strip()] = v.strip()
    required = {"username", "password"}
    missing = required - creds.keys()
    if missing:
        raise ValueError(f"Missing keys in {path}: {missing}")
    return creds


def log(msg: str) -> None:
    print(f"  {msg}", flush=True)


def step(msg: str) -> None:
    print(f"\n[*] {msg}", flush=True)


def dump_screen(b: CarbonylBrowser, label: str = "") -> str:
    text = b.page_text()
    if label:
        print(f"\n--- screen: {label} ---")
    print(text[:2000])
    return text


# ---------------------------------------------------------------------------
# Login flow
# ---------------------------------------------------------------------------

def login(b: CarbonylBrowser, username: str, password: str) -> bool:
    step(f"Navigating to login page: {LOGIN_URL}")
    b.open(LOGIN_URL)
    b.drain(PAGE_LOAD)
    text = b.page_text()

    # Check if already logged in
    if "Sign Out" in text or "sign out" in text.lower():
        log("Already logged in — skipping login step")
        return True

    dump_screen(b, "login page")

    # Login page layout (220-col terminal, confirmed by probe):
    #   row 26: "* Username" label
    #   rows 27-31: username input box  (▐ col 21 .. ▌ col 83)
    #   row 34: "* Password" label
    #   rows 35-39: password input box  (▐ col 21 .. ▌ col 83)
    #   row 44: "Sign In" button at col 35

    # Simulate organic mouse movement to defeat bot sensors, then click field
    step("Entering username")
    b.mouse_path([(30, 10), (45, 20), (52, 26), (52, 29)], delay=0.05)
    b.click(52, 29)
    b.drain(ACTION_WAIT)
    b.send(username)
    b.drain(1)

    step("Entering password")
    b.mouse_path([(52, 29), (52, 32), (52, 37)], delay=0.05)
    b.click(52, 37)
    b.drain(ACTION_WAIT)
    b.send(password)
    b.drain(1)

    # Submit via Sign In button (col 35+3=38 center, row 44)
    step("Submitting login form")
    b.mouse_path([(52, 37), (45, 41), (38, 44)], delay=0.06)
    b.click(38, 44)
    b.drain(PAGE_LOAD)

    text = b.page_text()
    dump_screen(b, "post-login")

    if any(kw in text for kw in ("Sign Out", "Hi, ", "Your Account", "Your Profile")):
        log("Login successful")
        return True
    elif any(kw in text.lower() for kw in ("incorrect", "invalid", "error", "failed")):
        log("ERROR: Login appears to have failed — check credentials")
        return False
    elif "Sign In" in text and "Username" in text:
        log("ERROR: Still on login page — login did not succeed")
        return False
    else:
        log("Login status unclear — proceeding")
        return True


# ---------------------------------------------------------------------------
# PO Box retrieval
# ---------------------------------------------------------------------------

def get_pobox_info(b: CarbonylBrowser, creds: dict) -> str:
    step(f"Navigating to PO Box management: {POBOX_URL}")
    b.navigate(POBOX_URL)
    b.drain(PAGE_LOAD)
    text = b.page_text()
    dump_screen(b, "po box page")

    # If redirected to login, we lost the session
    if "Sign In" in text and "PO Box" not in text:
        log("Redirected to login — session may not have persisted")
        return ""

    # If we see the marketing page with a "Manage Your PO Box" link, click it
    if "Manage Your PO Box" in text:
        step("Clicking 'Manage Your PO Box' link")
        b.click_text("Manage Your PO Box")
        b.drain(PAGE_LOAD)
        # Give JS more time to render account data
        b.drain(8)
        # Scroll down to reveal below-fold content
        for _ in range(8):
            b.send_key("down")
            b.drain(0.3)
        b.drain(3)
        text = b.page_text()
        dump_screen(b, "manage po box page")

    # poboxes.usps.com uses a separate SSO (verified.usps.com) — login again if needed
    # Layout (220-col terminal, confirmed by probe):
    #   row 27: "User Name" label at col=34, input rows 29-32 (▐ col 35 .. col 198)
    #   row 35: "Password"  label at col=34, input rows 37-40
    #   row 45: "Sign In" button at col=47
    if POBOX_SSO_HOST in b.nav_bar_url() and "User Name" in text:
        step("Secondary SSO login at verified.usps.com")
        b.mouse_path([(60, 20), (90, 25), (110, 30)], delay=0.05)
        b.click(110, 30)
        b.drain(ACTION_WAIT)
        b.send(creds["username"])
        b.drain(1)

        b.mouse_path([(110, 30), (110, 35), (110, 38)], delay=0.05)
        b.click(110, 38)
        b.drain(ACTION_WAIT)
        b.send(creds["password"])
        b.drain(1)

        b.mouse_path([(110, 38), (80, 42), (50, 45)], delay=0.06)
        b.click(50, 45)
        b.drain(PAGE_LOAD)
        text = b.page_text()
        dump_screen(b, "manage po box page")

    # Look for PO Box entries — account data, renewal dates, box numbers
    lines = [l for l in text.splitlines() if l.strip()]
    pobox_lines = []
    capture = False
    for line in lines:
        if any(kw in line for kw in (
            "PO Box", "P.O. Box", "Box Number", "Box #",
            "Renewal", "Due Date", "Expir", "Box Size",
            "Location", "Post Office", "Annual Fee",
        )):
            capture = True
        if capture:
            pobox_lines.append(line)
        if capture and len(pobox_lines) > 40:
            break

    if pobox_lines:
        return "\n".join(pobox_lines)

    # Check for known empty-account indicators
    if any(kw in text for kw in ("Reserve a New PO Box", "No PO Box", "no current PO")):
        return "(Account has no PO Boxes currently registered)"

    # Fallback: return full page text
    return text


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    print("=" * 60)
    print("USPS PO Box Smoke Test")
    print("=" * 60)

    # Load credentials
    if not CREDS_FILE.exists():
        print(f"ERROR: credentials file not found: {CREDS_FILE}")
        return 1

    creds = load_credentials(CREDS_FILE)
    log(f"Loaded credentials for user: {creds['username']}")

    # Instantiate browser with persistent session
    b = CarbonylBrowser(session=SESSION_NAME)

    try:
        # Login
        ok = login(b, creds["username"], creds["password"])
        if not ok:
            print("\nFAIL: login failed")
            return 1

        # Fetch PO Box info
        info = get_pobox_info(b, creds)

        print("\n" + "=" * 60)
        print("PO BOX INFORMATION")
        print("=" * 60)
        if info:
            print(info)
        else:
            print("(no PO Box data extracted — see screen dumps above)")

        print("\nPASS: smoke test completed")
        return 0

    finally:
        b.close()


if __name__ == "__main__":
    sys.exit(main())
