<div align="center">

<img width="100" height="100" alt="android_icon" src="https://github.com/user-attachments/assets/042fb5b1-8bcd-4f96-b9dd-16fe241930ba" styele="border-radius: 50%" />

<h1>Syne</h1>

<br />

<h3><b>Monitor and control your server remotely via phone</b></h3>

A lightweight app that allows server administration with a clean and simple mobile interface.

<a href="#features">Features</a> •
<a href="#installation">Installation</a> •
<a href="#usage">Usage</a> •
<a href="#screenshots">Screenshots</a> •
<a href="#contributing">Contributing</a>

</div>

---

## Overview

Syne is a lightweight, modern application designed to simplify server management over SSH. It provides an intuitive interface for monitoring system performance, managing files, and executing essential controls without relying on a terminal for routine tasks.

The app brings together key administrative functions into a unified dashboard, allowing users to view real-time system metrics such as CPU usage, memory consumption, disk utilization, and running processes. It also includes a built-in file explorer with support for uploading and downloading files, making remote file management seamless and efficient.

If you work with Linux systems regularly, you probably run:

```bash
top
df -h
````

multiple times a day.

**Syne** eliminates that repetition by bringing system monitoring and control directly to your phone.

---

## Installation

Install APK for android from <a href="https://github.com/tribhuwan-kumar/syne/releases/">release page</a>

---

## Features

#### Real-Time System Monitoring

* Live Telemetry:
Tracks CPU, GPU, RAM, and battery metrics.
Delivers sub-second latency using a Rust backend.
* Hardware & Thermals:
Monitors live system temperatures and kernel info.
Tracks architecture specs, load averages, and active sensors.

#### Universal Package Management

* Multi-OS Support:
Handles system updates out of the box.
Supports Arch, Ubuntu, Fedora, Alpine, openSUSE, macOS, and Windows.
* One-Click Batch Upgrades:
Check off exactly which packages you want to update.
Handles all downloads and updates in one go.
* Safe Sudo Handling:
Prompts for passwords safely.
Pipes input directly into the SSH session's stdin.
Keeps sensitive passwords completely out of your bash history.

#### Built-in Terminal Emulator

* Full Shell Experience:
Uses xterm.dart for terminal rendering.
Handles complex ANSI escape sequences and PTY outputs smoothly.
* Mobile-Friendly Keys:
Adds a handy, persistent shortcut row.
Quick access for CTRL, ALT, ESC, TAB, and arrow keys.
Saves you from fighting your default phone keyboard.
* TUI & Vim Ready:
Bypasses aggressive mobile autocorrect entirely.
Provides a 1:1 input pipeline for the terminal.
Makes command-line tools and text editors feel responsive.

#### Network & Traffic Tools

* Live Bandwidth Graphs:
Charts upload and download speeds on the fly.
Provides quick visual context for network activity.
* Interface Insights:
Displays active IP bindings and default routes.
Tracks link statuses, ping latency, and packet loss.
* Quick Port Scanner:
Scans your target system locally.
Gives an immediate list of open ports and active listeners.

#### Architecture & UX

* Smart Reconnections:
Uses background heartbeats to detect network drops.
Cleans up orphaned backend processes automatically.
* State Preservation:
Built around an IndexedStack navigation structure.
Keeps terminal sessions, search inputs, and scroll positions active.
Prevents pages from resetting when switching tabs.
* Multi-Host Support:
Built to manage multiple remote servers from one app.
Allows you to quickly jump between active connections.

---

## Requirements

* Any remote server with SSH enabled
* SSH credentials

Enable SSH on `systemd` machine:

```bash
systemctl enable --now sshd
systemctl start sshd
```

---

## Screenshots
<div align="center">
<table>
  
<tr>
<td><img src="https://github.com/user-attachments/assets/d024a4ce-b922-4c2e-bd7c-b1f9ee963dfb" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/26fb1c01-49f9-4ad1-9285-176dfff77cb3" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/b7ac970b-f89b-44ee-8950-6f368efea07a" width="250"/></td>
</tr>

<tr>
<td><img src="https://github.com/user-attachments/assets/486591aa-8ae8-4da6-96cf-72a6b404cf35" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/66a8155d-b88f-440d-b61d-da2cb5ee8993" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/20483f35-4107-40e3-937e-ee4377beec53" width="250"/></td>
</tr>

<tr>
<td><img src="https://github.com/user-attachments/assets/c8ded873-409c-493b-b903-c61d10078d84" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/32c5997c-e5dd-44f2-9a2d-a990ecacb925" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/ef89d9b3-7e79-4ad6-bc26-530845f354f3" width="250"/></td>
</tr>

<tr>
<td><img src="https://github.com/user-attachments/assets/dc20c668-6c37-4c69-a7dd-0927745cb64d" width="250"/></td>
<td><img src="https://github.com/user-attachments/assets/21a8cf74-00a6-4523-b5be-3476ef33362b" width="250"/></td>
</tr>

</table>
</div>

---

## Build:
- Clone the repository

```bash
git clone https://github.com/aniruddha76/syne.git && cd syne
```

- Install dependencies

```bash
flutter pub get
```

- Connect your phone

```bash
With Developer mode on
with USB debugging on
```

- Run the app

```bash
flutter run
```


#### Credits

I got the app idea from [aniruddha76](https://github.com/aniruddha76)

