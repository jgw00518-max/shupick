"""Interactively change only the SHUPICK test account's password."""

import getpass
import sys
import warnings
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials


def main():
    if not sys.stdin.isatty():
        raise RuntimeError("Run this tool directly in an interactive terminal.")
    warnings.simplefilter("error", getpass.GetPassWarning)
    key_path = Path("D:/grace2/shupick-secrets/firebase-admin.json")
    credential = credentials.Certificate(str(key_path))
    if credential.project_id != "shupick-71b8f":
        raise RuntimeError("Unexpected Firebase project; no changes made.")
    app = firebase_admin.initialize_app(credential)
    email = "shupicktest01@example.com"
    user = auth.get_user_by_email(email, app=app)
    if user.email != email or user.disabled:
        raise RuntimeError("Account mismatch or disabled; no changes made.")
    print(f"Target account: {email}")
    print("Only the password will change. Input is hidden; Ctrl+C cancels.")
    password = getpass.getpass("New password (at least 6 characters): ")
    confirmation = getpass.getpass("Enter the same password again: ")
    if len(password) < 6 or password != confirmation:
        raise ValueError("Passwords must match and contain at least 6 characters.")
    updated = auth.update_user(user.uid, password=password, app=app)
    if updated.uid != user.uid or updated.email != email:
        raise RuntimeError("Unexpected account response; check Firebase console.")
    print("SUCCESS: Password changed. The account UID is unchanged.")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("Cancelled.")
        sys.exit(1)
    except Exception as error:
        # Do not print API request details or any secret entered by the user.
        print(f"Reset did not complete ({type(error).__name__}).")
        sys.exit(1)
