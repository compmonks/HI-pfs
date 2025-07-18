#!/usr/bin/env python3
"""Simple GUI launcher for HI-pfs scripts fetched from GitHub."""
import subprocess
import os
import tkinter as tk
from tkinter import messagebox

TERMINAL = os.environ.get("TERMINAL", "x-terminal-emulator")

INSTALL_CMD = (
    "bash <(curl -fsSL "
    "https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/bootstrap.sh)"
)
DIAG_CMD = (
    "bash <(curl -fsSL "
    "https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/diagnostics.sh)"
)
DELETE_CMD = (
    "bash <(curl -fsSL "
    "https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/init.sh)"
)


def run_command(cmd: str) -> None:
    """Open a terminal and execute the provided command."""
    try:
        subprocess.Popen([TERMINAL, "-e", "bash", "-c", cmd])
    except FileNotFoundError:
        messagebox.showerror("Error", f"Terminal '{TERMINAL}' not found")


root = tk.Tk()
root.title("HI-pfs Launcher")
root.resizable(False, False)

btn_install = tk.Button(root, text="Install", width=20,
                        command=lambda: run_command(INSTALL_CMD))
btn_diag = tk.Button(root, text="Diagnostics & Tests", width=20,
                     command=lambda: run_command(DIAG_CMD))
btn_delete = tk.Button(root, text="Delete", width=20,
                       command=lambda: run_command(DELETE_CMD))

for btn in (btn_install, btn_diag, btn_delete):
    btn.pack(pady=5)

root.mainloop()
