"""
mock-controller/app.py
Replicates the HTTP API served by /sbin/controller on the real device.

Endpoints (from index.html JS):
  GET  /status   → {"status": bool, "onSchedule": str, "offSchedule": str, "currentTime": str}
  POST /on       → 200 OK
  POST /off      → 200 OK
  GET  /schedule?ontime=…&offtime=…&time=… → update schedules / system time

State is kept in memory only (lost on container restart).
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime, timedelta
import subprocess
import threading

app = Flask(__name__)
CORS(app)  # allow XHR from the firmware web-UI origin

# ── in-memory device state ────────────────────────────────────────────────────
_state = {
    "status": False,
    "on_schedule": "",
    "off_schedule": "",
    "time_offset": timedelta(0),   # delta applied on top of wall clock
}

CONTROLLER_LOG = "/tmp/controller.log"
_log_lock = threading.Lock()


def _log(lines: list) -> None:
    """Write plain simulated output lines to the controller log."""
    with _log_lock:
        with open(CONTROLLER_LOG, "a") as f:
            for line in lines:
                f.write(line + "\r\n")


def _exec_cmd(cmd: str) -> None:
    """Emulate what /sbin/controller does on the real firmware: passes the
    time argument directly to the shell via system().  This is intentionally
    unsafe to demonstrate command injection."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=5
        )
        output = (result.stdout + result.stderr).rstrip("\n")
    except subprocess.TimeoutExpired:
        output = "timeout"
    except Exception as e:
        output = f"error: {e}"
    with _log_lock:
        with open(CONTROLLER_LOG, "a") as f:
            f.write(f"\r\n\033[33m[controller]\033[0m $ {cmd}\r\n")
            if output:
                f.write(output + "\r\n")


def _current_time() -> str:
    return (datetime.now() + _state["time_offset"]).strftime("%Y-%m-%dT%H:%M")


@app.get("/status")
def get_status():
    return jsonify(
        status=_state["status"],
        onSchedule=_state["on_schedule"],
        offSchedule=_state["off_schedule"],
        currentTime=_current_time(),
    )


@app.post("/on")
def turn_on():
    _state["status"] = True
    threading.Thread(target=_log, args=([  # noqa: E501
        "",
        "\033[33m[controller]\033[0m \033[32mrelay_set(RELAY_MAIN, ON)\033[0m",
        "  gpio: writing 1 to /sys/class/gpio/gpio17/value",
        "  relay: MAIN → ON",
        "  httpd: 200 OK /on",
    ],), daemon=True).start()
    return "", 200


@app.post("/off")
def turn_off():
    _state["status"] = False
    threading.Thread(target=_log, args=([  # noqa: E501
        "",
        "\033[33m[controller]\033[0m \033[31mrelay_set(RELAY_MAIN, OFF)\033[0m",
        "  gpio: writing 0 to /sys/class/gpio/gpio17/value",
        "  relay: MAIN → OFF",
        "  httpd: 200 OK /off",
    ],), daemon=True).start()
    return "", 200


@app.route("/schedule", methods=["GET", "POST"])
def schedule():
    """
    The firmware page submits forms with fields:
      time    – new system time  (datetime-local string)
      ontime  – scheduled on     (datetime-local string)
      offtime – scheduled off    (datetime-local string)
    Any combination of the three can be present.
    """
    args = request.args if request.method == "GET" else request.form

    if "ontime" in args and args["ontime"]:
        val = args["ontime"]
        _state["on_schedule"] = val
        threading.Thread(target=_log, args=([  # noqa: E501
            "",
            f"\033[33m[controller]\033[0m schedule_set(ON,  \"{val}\")",
            f"  cron: added job → relay ON  at {val}",
            "  httpd: 200 OK /schedule",
        ],), daemon=True).start()
    if "offtime" in args and args["offtime"]:
        val = args["offtime"]
        _state["off_schedule"] = val
        threading.Thread(target=_log, args=([  # noqa: E501
            "",
            f"\033[33m[controller]\033[0m schedule_set(OFF, \"{val}\")",
            f"  cron: added job → relay OFF at {val}",
            "  httpd: 200 OK /schedule",
        ],), daemon=True).start()
    if "time" in args and args["time"]:
        time_val = args["time"]
        try:
            target = datetime.fromisoformat(time_val)
            _state["time_offset"] = target - datetime.now()
        except ValueError:
            pass
        # Emulate the real firmware: /sbin/controller calls system() with the
        # time parameter inserted directly into a shell command - no sanitization.
        cmd = f'date -s "{time_val}"'
        threading.Thread(target=_exec_cmd, args=(cmd,), daemon=True).start()

    return jsonify(
        status=_state["status"],
        onSchedule=_state["on_schedule"],
        offSchedule=_state["off_schedule"],
        currentTime=_current_time(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
