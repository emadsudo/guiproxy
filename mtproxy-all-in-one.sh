#!/usr/bin/env bash
# ==============================================================================
# MTProxy Ultimate Suite (C Engine + Bulletproof CLI + Hardened Web GUI)
# HTTP Copy-Safe | Sponsor Managed Strictly via CLI
# ==============================================================================

INSTALL_DIR="/opt/mtproxy"
BIN_PATH="$INSTALL_DIR/mtproto-proxy"
SERVICE_FILE="/etc/systemd/system/mtproxy.service"
GUI_SERVICE_FILE="/etc/systemd/system/mtproxy-gui.service"
CONFIG_FILE="$INSTALL_DIR/config.env"
GUI_CONFIG_FILE="$INSTALL_DIR/gui.env"
GUI_PY_PATH="$INSTALL_DIR/web-gui.py"
CLI_PATH="/usr/local/bin/mtproxy-cli"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[Error] This script must be run as root (sudo).${NC}"
    exit 1
fi

get_public_ip() {
    curl -4 -s --connect-timeout 5 ifconfig.me || curl -4 -s api.ipify.org || echo "YOUR_SERVER_IP"
}

select_tls_domain() {
    while true; do
        echo -e "\n${CYAN}=== Select Fake-TLS Spoofing Website ===${NC}"
        echo "Recommended Domains:"
        echo "  1) www.samsung.com (Recommended)"
        echo "  2) www.cloudflare.com"
        echo "  3) www.apple.com"
        echo "  4) www.microsoft.com"
        echo "  5) Custom Domain"
        read -p "Choose domain [1-5, Default: 1]: " DOM_CHOICE
        DOM_CHOICE=$(echo "$DOM_CHOICE" | tr -d '[:space:]')
        DOM_CHOICE=${DOM_CHOICE:-1}

        case $DOM_CHOICE in
            1) TLS_DOMAIN="www.samsung.com"; break ;;
            2) TLS_DOMAIN="www.cloudflare.com"; break ;;
            3) TLS_DOMAIN="www.apple.com"; break ;;
            4) TLS_DOMAIN="www.microsoft.com"; break ;;
            5)
                read -p "Enter custom domain (e.g., cdn.jsdelivr.net): " TLS_DOMAIN
                TLS_DOMAIN=$(echo "$TLS_DOMAIN" | tr -d '[:space:]')
                if [[ "$TLS_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    break
                else
                    echo -e "${RED}[Error] Invalid domain format! Try again.${NC}"
                fi
                ;;
            *) echo -e "${RED}[Error] Invalid selection. Please enter 1-5.${NC}" ;;
        esac
    done
}

update_systemd_service() {
    source "$CONFIG_FILE"
    TAG_FLAG=""
    if [[ -n "$PROXY_TAG" ]]; then
        TAG_FLAG="-P $PROXY_TAG"
    fi

    printf '%s\n' \
        "[Unit]" \
        "Description=MTProxy Telegram Proxy Daemon" \
        "After=network.target" \
        "" \
        "[Service]" \
        "Type=simple" \
        "User=mtproxy" \
        "Group=mtproxy" \
        "WorkingDirectory=$INSTALL_DIR" \
        "EnvironmentFile=$CONFIG_FILE" \
        "ExecStart=/bin/sh -c 'exec $BIN_PATH -u mtproxy -p \${STATS_PORT} -H \${PORT} -S \${RAW_SECRET} -D \${TLS_DOMAIN} $TAG_FLAG --aes-pwd proxy-secret proxy-multi.conf -M \${WORKERS}'" \
        "Restart=always" \
        "RestartSec=3" \
        "LimitNOFILE=65535" \
        "" \
        "[Install]" \
        "WantedBy=multi-user.target" > "$SERVICE_FILE"

    systemctl daemon-reload
}

deploy_web_gui_backend() {
    tee "$GUI_PY_PATH" > /dev/null << 'PYEOF'
#!/usr/bin/env python3
import os
import subprocess
import psutil
import urllib.request
from functools import wraps
from flask import Flask, request, jsonify, render_template_string, Response

app = Flask(__name__)

GUI_USER = os.getenv("GUI_USER", "admin")
GUI_PASS = os.getenv("GUI_PASS", "redteam2026")
CONFIG_FILE = "/opt/mtproxy/config.env"

def check_auth(username, password):
    return username == GUI_USER and password == GUI_PASS

def authenticate():
    return Response(
        'Access Denied: Valid Authentication Credentials Required.\n', 401,
        {'WWW-Authenticate': 'Basic realm="MTProxy Control Dashboard"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

def read_env_config():
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            for line in f:
                if "=" in line and not line.strip().startswith("#"):
                    k, v = line.strip().split("=", 1)
                    cfg[k] = v.strip('"')
    return cfg

def get_public_ip():
    try:
        return urllib.request.urlopen('https://api.ipify.org', timeout=3).read().decode('utf8')
    except:
        return "YOUR_SERVER_IP"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MTProxy Red-Team Command Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        dark: { 900: '#0a0a0c', 800: '#121216', 700: '#1a1a22' },
                        crimson: { 500: '#e60000', 600: '#b30000', 400: '#ff3333' }
                    }
                }
            }
        }
    </script>
    <style>
        body { background-color: #0a0a0c; color: #e5e7eb; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
        .red-glow { box-shadow: 0 0 15px rgba(230, 0, 0, 0.25); border: 1px solid rgba(230, 0, 0, 0.4); }
        .red-glow-sm { box-shadow: 0 0 8px rgba(230, 0, 0, 0.15); border: 1px solid rgba(230, 0, 0, 0.3); }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: #121216; }
        ::-webkit-scrollbar-thumb { background: #b30000; border-radius: 3px; }
    </style>
</head>
<body class="min-h-screen p-6">
    <div class="max-w-7xl mx-auto space-y-6">
        <header class="flex justify-between items-center bg-dark-800 p-5 rounded-xl red-glow">
            <div class="flex items-center space-x-3">
                <div class="w-3 h-3 rounded-full bg-crimson-500 animate-pulse"></div>
                <h1 class="text-xl font-bold tracking-wider text-white">MTPROXY <span class="text-crimson-400">CORE CONTROLLER</span></h1>
            </div>
            <div id="status-badge" class="px-4 py-1.5 rounded-full text-xs font-semibold bg-dark-700 border border-gray-700">Checking...</div>
        </header>

        <!-- Metrics Grid -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div class="bg-dark-800 p-4 rounded-xl red-glow-sm flex flex-col justify-between">
                <span class="text-xs text-gray-400 font-semibold uppercase">CPU Usage</span>
                <div class="flex items-baseline justify-between mt-2">
                    <span id="cpu-val" class="text-2xl font-bold text-crimson-400">0%</span>
                    <div class="w-24 bg-dark-700 h-2 rounded-full overflow-hidden">
                        <div id="cpu-bar" class="bg-crimson-500 h-full transition-all duration-300" style="width: 0%"></div>
                    </div>
                </div>
            </div>
            <div class="bg-dark-800 p-4 rounded-xl red-glow-sm flex flex-col justify-between">
                <span class="text-xs text-gray-400 font-semibold uppercase">RAM Usage</span>
                <div class="flex items-baseline justify-between mt-2">
                    <span id="ram-val" class="text-2xl font-bold text-crimson-400">0 MB</span>
                    <span id="ram-pct" class="text-xs text-gray-400">0%</span>
                </div>
            </div>
            <div class="bg-dark-800 p-4 rounded-xl red-glow-sm flex flex-col justify-between">
                <span class="text-xs text-gray-400 font-semibold uppercase">Active Clients</span>
                <span id="clients-val" class="text-2xl font-bold text-white mt-2">0</span>
            </div>
            <div class="bg-dark-800 p-4 rounded-xl red-glow-sm flex flex-col justify-between">
                <span class="text-xs text-gray-400 font-semibold uppercase">Core Load Factor</span>
                <span id="load-val" class="text-2xl font-bold text-white mt-2">0.00</span>
            </div>
        </div>

        <!-- Better Active Link Controller Section -->
        <div class="bg-dark-800 p-6 rounded-xl red-glow space-y-4">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-crimson-400">Active Connection Link Controller</h2>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                
                <!-- Fake-TLS Card -->
                <div class="bg-dark-900 p-4 rounded-lg border border-gray-800 flex flex-col justify-between space-y-2">
                    <div>
                        <div class="flex justify-between items-center mb-2">
                            <span class="text-xs font-bold text-green-400">FAKE-TLS (RECOMMENDED)</span>
                            <span id="domain-lbl" class="text-[10px] bg-dark-800 px-2 py-0.5 rounded text-gray-300"></span>
                        </div>
                        <label class="text-[10px] text-gray-400">Connection Link:</label>
                        <div class="flex space-x-1 mt-0.5">
                            <input id="tls-link" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-[11px] text-gray-300 font-mono select-all">
                            <button onclick="copyVal('tls-link')" class="bg-dark-700 hover:bg-dark-800 border border-gray-600 text-white text-[11px] px-2.5 rounded font-semibold transition">Copy</button>
                        </div>
                        <label class="text-[10px] text-gray-400 mt-2 block">Link Secret:</label>
                        <div class="flex space-x-1 mt-0.5">
                            <input id="tls-sec" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-[11px] text-green-400 font-mono select-all">
                            <button onclick="copyVal('tls-sec')" class="bg-dark-700 hover:bg-dark-800 border border-gray-600 text-green-400 text-[11px] px-2.5 rounded font-semibold transition">Copy</button>
                        </div>
                    </div>
                </div>

                <!-- Random Padding Card -->
                <div class="bg-dark-900 p-4 rounded-lg border border-gray-800 flex flex-col justify-between space-y-2">
                    <div>
                        <div class="flex justify-between items-center mb-2">
                            <span class="text-xs font-bold text-yellow-400">RANDOM PADDING (dd)</span>
                        </div>
                        <label class="text-[10px] text-gray-400">Connection Link:</label>
                        <div class="flex space-x-1 mt-0.5">
                            <input id="dd-link" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-[11px] text-gray-300 font-mono select-all">
                            <button onclick="copyVal('dd-link')" class="bg-dark-700 hover:bg-dark-800 border border-gray-600 text-white text-[11px] px-2.5 rounded font-semibold transition">Copy</button>
                        </div>
                        <label class="text-[10px] text-gray-400 mt-2 block">Link Secret:</label>
                        <div class="flex space-x-1 mt-0.5">
                            <input id="dd-sec" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-[11px] text-yellow-400 font-mono select-all">
                            <button onclick="copyVal('dd-sec')" class="bg-dark-700 hover:bg-dark-800 border border-gray-600 text-yellow-400 text-[11px] px-2.5 rounded font-semibold transition">Copy</button>
                        </div>
                    </div>
                </div>

                <!-- Standard Card -->
                <div class="bg-dark-900 p-4 rounded-lg border border-gray-800 flex flex-col justify-between space-y-2">
                    <div>
                        <div class="flex justify-between items-center mb-2">
                            <span class="text-xs font-bold text-gray-400">STANDARD MTPROTO</span>
                        </div>
                        <label class="text-[10px] text-gray-400">Connection Link:</label>
                        <div class="flex space-x-1 mt-0.5">
                            <input id="std-link" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-[11px] text-gray-300 font-mono select-all">
                            <button onclick="copyVal('std-link')" class="bg-dark-700 hover:bg-dark-800 border border-gray-600 text-white text-[11px] px-2.5 rounded font-semibold transition">Copy</button>
                        </div>
                        <label class="text-[10px] text-gray-400 mt-2 block">Link Secret:</label>
                        <div class="flex space-x-1 mt-0.5">
                            <input id="std-sec" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-[11px] text-gray-400 font-mono select-all">
                            <button onclick="copyVal('std-sec')" class="bg-dark-700 hover:bg-dark-800 border border-gray-600 text-gray-400 text-[11px] px-2.5 rounded font-semibold transition">Copy</button>
                        </div>
                    </div>
                </div>

            </div>
        </div>

        <!-- Controls & Logs -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="bg-dark-800 p-6 rounded-xl red-glow space-y-4">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-crimson-400">System Controls</h2>
                
                <!-- Raw Secret Box for @MTProxybot -->
                <div class="bg-dark-900 p-3 rounded-lg border border-crimson-500/50 space-y-1">
                    <div class="flex justify-between items-center">
                        <span class="text-xs font-bold text-crimson-400">RAW BASE SECRET (For @MTProxybot registration)</span>
                        <button onclick="copyVal('raw-sec-val')" class="text-[11px] bg-crimson-600 hover:bg-crimson-500 px-2.5 py-1 rounded text-white font-semibold transition">Copy Raw Secret</button>
                    </div>
                    <input id="raw-sec-val" readonly class="w-full bg-dark-800 border border-gray-700 rounded p-1.5 text-xs text-yellow-400 font-mono select-all mt-1">
                </div>

                <div class="grid grid-cols-2 gap-3 pt-1">
                    <button onclick="sendAction('restart')" class="bg-dark-700 hover:bg-dark-900 border border-gray-600 hover:border-crimson-500 text-white py-2.5 rounded-lg text-xs font-semibold transition">RESTART ENGINE</button>
                    <button onclick="sendAction('regen_secret')" class="bg-dark-700 hover:bg-dark-900 border border-gray-600 hover:border-crimson-500 text-white py-2.5 rounded-lg text-xs font-semibold transition">NEW SECRET</button>
                </div>
                <div class="space-y-3 pt-2">
                    <div class="flex space-x-2">
                        <input id="input-port" type="number" placeholder="New Client Port (e.g. 443)" class="flex-1 bg-dark-900 border border-gray-700 rounded p-2 text-xs text-white">
                        <button onclick="sendAction('change_port', document.getElementById('input-port').value)" class="bg-crimson-600 hover:bg-crimson-500 px-4 py-2 rounded text-xs font-semibold text-white transition">SET PORT</button>
                    </div>
                    <div class="flex space-x-2">
                        <input id="input-domain" type="text" placeholder="New Spoof Domain (e.g. apple.com)" class="flex-1 bg-dark-900 border border-gray-700 rounded p-2 text-xs text-white">
                        <button onclick="sendAction('change_domain', document.getElementById('input-domain').value)" class="bg-crimson-600 hover:bg-crimson-500 px-4 py-2 rounded text-xs font-semibold text-white transition">SET DOMAIN</button>
                    </div>
                </div>
            </div>

            <div class="bg-dark-800 p-6 rounded-xl red-glow flex flex-col h-96">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-crimson-400 mb-3">Live Service Logs</h2>
                <pre id="log-console" class="flex-1 bg-dark-900 border border-gray-800 rounded-lg p-3 text-xs text-gray-400 overflow-y-auto font-mono whitespace-pre-wrap"></pre>
            </div>
        </div>
    </div>

    <script>
        function copyVal(id) {
            const el = document.getElementById(id);
            if (!el || !el.value) return;
            
            // HTTP Copy Fallback Engine
            const temp = document.createElement("textarea");
            temp.value = el.value;
            temp.style.position = "fixed";
            temp.style.left = "-999999px";
            document.body.appendChild(temp);
            temp.focus();
            temp.select();
            try {
                document.execCommand('copy');
                alert('Copied to clipboard!');
            } catch (err) {
                alert('Failed to auto-copy. Please select manually.');
            }
            document.body.removeChild(temp);
        }

        async function fetchStats() {
            try {
                const res = await fetch('/api/stats');
                const data = await res.json();
                document.getElementById('cpu-val').innerText = data.cpu + '%';
                document.getElementById('cpu-bar').style.width = data.cpu + '%';
                document.getElementById('ram-val').innerText = data.ram_mb + ' MB';
                document.getElementById('ram-pct').innerText = data.ram_pct + '%';
                document.getElementById('clients-val').innerText = data.clients;
                document.getElementById('load-val').innerText = data.load;
                
                const badge = document.getElementById('status-badge');
                if (data.active) {
                    badge.innerText = '● ENGINE RUNNING';
                    badge.className = 'px-4 py-1.5 rounded-full text-xs font-semibold bg-green-950 text-green-400 border border-green-800';
                } else {
                    badge.innerText = '● ENGINE OFFLINE';
                    badge.className = 'px-4 py-1.5 rounded-full text-xs font-semibold bg-red-950 text-red-400 border border-red-800';
                }

                if (data.links) {
                    document.getElementById('tls-link').value = data.links.tls_link;
                    document.getElementById('tls-sec').value = data.links.tls_sec;
                    document.getElementById('dd-link').value = data.links.dd_link;
                    document.getElementById('dd-sec').value = data.links.dd_sec;
                    document.getElementById('std-link').value = data.links.std_link;
                    document.getElementById('std-sec').value = data.links.raw;
                    document.getElementById('raw-sec-val').value = data.links.raw;
                    document.getElementById('domain-lbl').innerText = data.links.domain;
                }
            } catch (e) {}
        }

        async function fetchLogs() {
            try {
                const res = await fetch('/api/logs');
                const text = await res.text();
                document.getElementById('log-console').innerText = text;
            } catch(e) {}
        }

        async function sendAction(action, val='') {
            if(!confirm(`Execute action: ${action.toUpperCase()}?`)) return;
            const formData = new FormData();
            formData.append('action', action);
            formData.append('value', val);
            await fetch('/api/action', { method: 'POST', body: formData });
            fetchStats();
            fetchLogs();
        }

        setInterval(fetchStats, 2000);
        setInterval(fetchLogs, 5000);
        fetchStats();
        fetchLogs();
    </script>
</body>
</html>
"""

@app.route("/")
@requires_auth
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route("/api/stats")
@requires_auth
def api_stats():
    cpu = psutil.cpu_percent(interval=None)
    mem = psutil.virtual_memory()
    active = subprocess.call(["systemctl", "is-active", "--quiet", "mtproxy"]) == 0
    clients = "0"
    load = "0.00"
    cfg = read_env_config()
    stats_port = cfg.get("STATS_PORT", "8888")
    try:
        req = urllib.request.urlopen(f"http://127.0.0.1:{stats_port}/stats", timeout=1)
        lines = req.read().decode("utf8").split("\n")
        for l in lines:
            if "total_special_connections" in l:
                clients = l.split("\t")[1]
            elif "load_average_total" in l:
                load = l.split("\t")[1]
    except:
        pass

    pub_ip = get_public_ip()
    port = cfg.get("PORT", "443")
    raw = cfg.get("RAW_SECRET", "")
    domain = cfg.get("TLS_DOMAIN", "www.samsung.com")
    dom_hex = domain.encode("utf-8").hex()
    
    tls_sec = f"ee{raw}{dom_hex}"
    dd_sec = f"dd{raw}"

    links = {
        "tls_link": f"tg://proxy?server={pub_ip}&port={port}&secret={tls_sec}",
        "tls_sec": tls_sec,
        "dd_link": f"tg://proxy?server={pub_ip}&port={port}&secret={dd_sec}",
        "dd_sec": dd_sec,
        "std_link": f"tg://proxy?server={pub_ip}&port={port}&secret={raw}",
        "raw": raw,
        "domain": domain
    }
    return jsonify({
        "cpu": round(cpu, 1),
        "ram_mb": int(mem.used / 1024 / 1024),
        "ram_pct": round(mem.percent, 1),
        "active": active,
        "clients": clients,
        "load": load,
        "links": links
    })

@app.route("/api/logs")
@requires_auth
def api_logs():
    try:
        return subprocess.check_output(["journalctl", "-u", "mtproxy", "-n", "35", "--no-pager"]).decode("utf8")
    except:
        return "Failed to read systemd logs."

@app.route("/api/action", methods=["POST"])
@requires_auth
def api_action():
    act = request.form.get("action")
    val = request.form.get("value", "").strip()
    cfg = read_env_config()

    if act == "restart":
        subprocess.call(["systemctl", "restart", "mtproxy"])
    elif act == "regen_secret":
        new_sec = os.urandom(16).hex()
        subprocess.call(["sed", "-i", f"s/^RAW_SECRET=.*/RAW_SECRET=\"{new_sec}\"/", CONFIG_FILE])
        subprocess.call(["systemctl", "restart", "mtproxy"])
    elif act == "change_port" and val.isdigit() and 1 <= int(val) <= 65535:
        subprocess.call(["sed", "-i", f"s/^PORT=.*/PORT={val}/", CONFIG_FILE])
        subprocess.call(["systemctl", "restart", "mtproxy"])
    elif act == "change_domain" and "." in val:
        subprocess.call(["sed", "-i", f"s/^TLS_DOMAIN=.*/TLS_DOMAIN=\"{val}\"/", CONFIG_FILE])
        subprocess.call(["systemctl", "restart", "mtproxy"])

    return jsonify({"status": "ok"})

if __name__ == "__main__":
    port = int(os.getenv("GUI_PORT", 8080))
    app.run(host="0.0.0.0", port=port)
PYEOF
    chmod +x "$GUI_PY_PATH"
}

install_mtproxy() {
    clear
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${CYAN}    Installing MTProxy Core + Web GUI Dashboard               ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    
    echo -e "${GREEN}[1/7] Installing system packages & Python engines...${NC}"
    apt-get update -q
    apt-get install -y -q git curl build-essential libssl-dev zlib1g-dev xxd cron python3-flask python3-psutil

    echo -e "${GREEN}[2/7] Compiling C Engine from source (GCC 11+ patched)...${NC}"
    rm -rf /tmp/MTProxy
    git clone --depth=1 https://github.com/TelegramMessenger/MTProxy.git /tmp/MTProxy
    cd /tmp/MTProxy
    sed -i 's/COMMON_CFLAGS = /COMMON_CFLAGS = -fcommon /g' Makefile
    sed -i 's/COMMON_LDFLAGS = /COMMON_LDFLAGS = -fcommon /g' Makefile
    make clean && make

    mkdir -p "$INSTALL_DIR"
    cp -f objs/bin/mtproto-proxy "$BIN_PATH"
    chmod +x "$BIN_PATH"
    cd ~ && rm -rf /tmp/MTProxy

    echo -e "${GREEN}[3/7] Fetching Telegram infrastructure configs...${NC}"
    curl -s https://core.telegram.org/getProxySecret -o "$INSTALL_DIR/proxy-secret"
    curl -s https://core.telegram.org/getProxyConfig -o "$INSTALL_DIR/proxy-multi.conf"

    printf '%s\n' \
        '#!/bin/bash' \
        'curl -s https://core.telegram.org/getProxyConfig -o /opt/mtproxy/proxy-multi.conf' \
        'systemctl reload-or-restart mtproxy.service' > /etc/cron.daily/mtproxy-update
    chmod +x /etc/cron.daily/mtproxy-update

    echo -e "${GREEN}[4/7] Creating system user & configuring proxy...${NC}"
    id -u mtproxy &>/dev/null || useradd -r -s /bin/false mtproxy
    chown -R mtproxy:mtproxy "$INSTALL_DIR"

    while true; do
        read -p "Enter listening port for Telegram clients [Default: 443]: " RAW_CLIENT
        RAW_CLIENT=$(echo "$RAW_CLIENT" | tr -d '[:space:]')
        CLIENT_PORT=${RAW_CLIENT:-443}
        if [[ "$CLIENT_PORT" =~ ^[0-9]+$ ]] && (( CLIENT_PORT >= 1 && CLIENT_PORT <= 65535 )); then
            echo -e "${GREEN}Selected Client Port: ${CLIENT_PORT}${NC}"
            break
        else
            echo -e "${RED}[Error] '${CLIENT_PORT}' is not a valid numeric port (1-65535). Try again.${NC}"
        fi
    done

    while true; do
        read -p "Enter Web Dashboard port [Default: 8080]: " RAW_GUI
        RAW_GUI=$(echo "$RAW_GUI" | tr -d '[:space:]')
        GUI_PORT=${RAW_GUI:-8080}
        if [[ "$GUI_PORT" =~ ^[0-9]+$ ]] && (( GUI_PORT >= 1 && GUI_PORT <= 65535 )); then
            echo -e "${GREEN}Selected Web GUI Port: ${GUI_PORT}${NC}"
            break
        else
            echo -e "${RED}[Error] '${GUI_PORT}' is not a valid numeric port (1-65535). Try again.${NC}"
        fi
    done

    STATS_PORT=8888
    select_tls_domain
    RAW_SECRET=$(head -c 16 /dev/urandom | xxd -ps)

    printf '%s\n' \
        "PORT=$CLIENT_PORT" \
        "STATS_PORT=$STATS_PORT" \
        "RAW_SECRET=\"$RAW_SECRET\"" \
        "TLS_DOMAIN=\"$TLS_DOMAIN\"" \
        "PROXY_TAG=\"\"" \
        "WORKERS=1" > "$CONFIG_FILE"

    echo -e "${GREEN}[5/7] Deploying MTProxy Core systemd service...${NC}"
    update_systemd_service
    systemctl enable --now mtproxy

    echo -e "${GREEN}[6/7] Deploying Dark & Crimson Red Web Dashboard...${NC}"
    deploy_web_gui_backend

    RAND_USER="admin_$(head -c 2 /dev/urandom | xxd -ps)"
    RAND_PASS=$(head -c 8 /dev/urandom | xxd -ps)

    printf '%s\n' \
        "GUI_PORT=$GUI_PORT" \
        "GUI_USER=\"$RAND_USER\"" \
        "GUI_PASS=\"$RAND_PASS\"" > "$GUI_CONFIG_FILE"

    printf '%s\n' \
        "[Unit]" \
        "Description=MTProxy Red-Team Web Dashboard" \
        "After=network.target" \
        "" \
        "[Service]" \
        "Type=simple" \
        "User=root" \
        "EnvironmentFile=$GUI_CONFIG_FILE" \
        "ExecStart=/usr/bin/python3 $GUI_PY_PATH" \
        "Restart=always" \
        "RestartSec=3" \
        "" \
        "[Install]" \
        "WantedBy=multi-user.target" > "$GUI_SERVICE_FILE"

    systemctl daemon-reload
    systemctl enable --now mtproxy-gui

    cp -f "$0" "$CLI_PATH"
    chmod +x "$CLI_PATH"

    echo -e "${GREEN}[7/7] Installation Fully Complete!${NC}"
    show_links
    read -p "Press Enter to return to menu..."
}

show_links() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}MTProxy is not configured yet.${NC}"
        return
    fi
    source "$CONFIG_FILE"
    PUB_IP=$(get_public_ip)
    DOMAIN_HEX=$(echo -n "$TLS_DOMAIN" | xxd -ps | tr -d '\n')
    FAKE_TLS_SECRET="ee${RAW_SECRET}${DOMAIN_HEX}"

    echo -e "\n${CYAN}==================================================================${NC}"
    echo -e "${CYAN}                 MTPROXY ACTIVE SYSTEM STATUS                     ${NC}"
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "Spoofing Website: ${YELLOW}${TLS_DOMAIN}${NC}"
    echo -e "Sponsor Tag:      ${GREEN}${PROXY_TAG:-None configured}${NC}"
    echo -e "Raw Base Secret:  ${YELLOW}${RAW_SECRET}${NC}  <-- Use in @MTProxybot"
    echo "------------------------------------------------------------------"
    echo -e "${GREEN}[1] FAKE-TLS LINK (Recommended for Anti-DPI):${NC}"
    echo -e "tg://proxy?server=${PUB_IP}&port=${PORT}&secret=${FAKE_TLS_SECRET}"
    echo ""
    echo -e "${YELLOW}[2] RANDOM PADDING LINK:${NC}"
    echo -e "tg://proxy?server=${PUB_IP}&port=${PORT}&secret=dd${RAW_SECRET}"
    echo ""
    echo -e "${CYAN}[3] STANDARD LINK:${NC}"
    echo -e "tg://proxy?server=${PUB_IP}&port=${PORT}&secret=${RAW_SECRET}"
    
    if [[ -f "$GUI_CONFIG_FILE" ]]; then
        source "$GUI_CONFIG_FILE"
        echo "------------------------------------------------------------------"
        echo -e "${CYAN}Web Dashboard URL:${NC} http://${PUB_IP}:${GUI_PORT}"
        echo -e "${CYAN}GUI Username:${NC}      ${GREEN}${GUI_USER}${NC}"
        echo -e "${CYAN}GUI Password:${NC}      ${GREEN}${GUI_PASS}${NC}"
    fi
    echo -e "${CYAN}==================================================================${NC}"
}

manage_links_interactive() {
    if [[ ! -f "$CONFIG_FILE" ]]; then echo -e "${RED}MTProxy not configured.${NC}"; sleep 1; return; fi
    source "$CONFIG_FILE"
    PUB_IP=$(get_public_ip)
    DOMAIN_HEX=$(echo -n "$TLS_DOMAIN" | xxd -ps | tr -d '\n')
    FAKE_TLS_SECRET="ee${RAW_SECRET}${DOMAIN_HEX}"

    while true; do
        clear
        echo -e "${CYAN}==============================================================${NC}"
        echo -e "${CYAN}              Active Link Interactive Controller               ${NC}"
        echo -e "${CYAN}==============================================================${NC}"
        echo -e "Select a link profile to inspect and copy exact credentials:"
        echo -e "  1) ${GREEN}Fake-TLS Mode${NC} (Best against DPI firewalls)"
        echo -e "  2) ${YELLOW}Random Padding Mode${NC} (Basic ISP size obfuscation)"
        echo -e "  3) ${CYAN}Standard Mode${NC} (Raw MTProto connection)"
        echo -e "  4) Display Raw Secret ONLY (For @MTProxybot)"
        echo -e "  0) Back to Main Menu"
        echo "--------------------------------------------------------------"
        read -p "Choose link option [0-4]: " L_OPT
        L_OPT=$(echo "$L_OPT" | tr -d '[:space:]')

        case $L_OPT in
            1)
                echo -e "\n${GREEN}=== FAKE-TLS LINK PROFILE ===${NC}"
                echo -e "Full Link:   tg://proxy?server=${PUB_IP}&port=${PORT}&secret=${FAKE_TLS_SECRET}"
                echo -e "Link Secret: ${FAKE_TLS_SECRET}"
                echo -e "Target SNI:  ${TLS_DOMAIN}"
                read -p "Press Enter to return to link list..." ;;
            2)
                echo -e "\n${YELLOW}=== RANDOM PADDING LINK PROFILE ===${NC}"
                echo -e "Full Link:   tg://proxy?server=${PUB_IP}&port=${PORT}&secret=dd${RAW_SECRET}"
                echo -e "Link Secret: dd${RAW_SECRET}"
                read -p "Press Enter to return to link list..." ;;
            3)
                echo -e "\n${CYAN}=== STANDARD LINK PROFILE ===${NC}"
                echo -e "Full Link:   tg://proxy?server=${PUB_IP}&port=${PORT}&secret=${RAW_SECRET}"
                echo -e "Link Secret: ${RAW_SECRET}"
                read -p "Press Enter to return to link list..." ;;
            4)
                echo -e "\n${YELLOW}=== RAW BASE SECRET FOR @MTProxybot ===${NC}"
                echo -e "Copy exactly this value into Telegram's admin bot:"
                echo -e "${GREEN}${RAW_SECRET}${NC}"
                read -p "Press Enter to return to link list..." ;;
            0) break ;;
            *) echo -e "${RED}Invalid selection.${NC}"; sleep 1 ;;
        esac
    done
}

manage_sponsor() {
    source "$CONFIG_FILE"
    PUB_IP=$(get_public_ip)
    echo -e "\n${CYAN}=== Configure Sponsor Channel ===${NC}"
    echo "1. Open Telegram and message: @MTProxybot -> /newproxy"
    echo -e "2. Send Server IP & Port: ${GREEN}${PUB_IP}:${PORT}${NC}"
    echo -e "3. Send Base Secret:      ${GREEN}${RAW_SECRET}${NC}"
    read -p "Enter Proxy Tag from bot (Leave blank to remove): " NEW_TAG
    NEW_TAG=$(echo "$NEW_TAG" | tr -d '[:space:]')

    if [[ -n "$NEW_TAG" && ! "$NEW_TAG" =~ ^[a-fA-F0-9]{32}$ ]]; then
        echo -e "${RED}[Error] Invalid tag format! Returning safely to menu...${NC}"
        sleep 2; return
    fi

    if grep -q "^PROXY_TAG=" "$CONFIG_FILE"; then
        sed -i "s/^PROXY_TAG=.*/PROXY_TAG=\"$NEW_TAG\"/" "$CONFIG_FILE"
    else
        printf '%s\n' "PROXY_TAG=\"$NEW_TAG\"" >> "$CONFIG_FILE"
    fi
    update_systemd_service && systemctl restart mtproxy
    echo -e "${GREEN}Sponsor configuration updated!${NC}"; read -p "Press Enter to return..."
}

change_tls_domain() {
    source "$CONFIG_FILE"
    select_tls_domain
    sed -i "s/^TLS_DOMAIN=.*/TLS_DOMAIN=\"$TLS_DOMAIN\"/" "$CONFIG_FILE"
    update_systemd_service && systemctl restart mtproxy
    echo -e "${GREEN}Domain updated! Service restarted.${NC}"; read -p "Press Enter to return..."
}

regenerate_secret() {
    source "$CONFIG_FILE"
    read -p "Are you sure you want to regenerate secrets? All users will disconnect (y/n): " CONF
    CONF=$(echo "$CONF" | tr -d '[:space:]')
    if [[ "$CONF" =~ ^[Yy]$ ]]; then
        NEW_RAW=$(head -c 16 /dev/urandom | xxd -ps)
        sed -i "s/^RAW_SECRET=.*/RAW_SECRET=\"$NEW_RAW\"/" "$CONFIG_FILE"
        update_systemd_service && systemctl restart mtproxy
        echo -e "${GREEN}New base secret generated!${NC}"; show_links
    fi
    read -p "Press Enter to return..."
}

change_client_port() {
    source "$CONFIG_FILE"
    read -p "New external client port [Current: $PORT]: " NEW_PORT
    NEW_PORT=$(echo "$NEW_PORT" | tr -d '[:space:]')
    NEW_PORT=${NEW_PORT:-$PORT}
    if ! ([[ "$NEW_PORT" =~ ^[0-9]+$ ]] && (( NEW_PORT >= 1 && NEW_PORT <= 65535 ))); then
        echo -e "${RED}[Error] Invalid port! Returning safely without changes.${NC}"
        sleep 2; return
    fi
    sed -i "s/^PORT=.*/PORT=$NEW_PORT/" "$CONFIG_FILE"
    update_systemd_service && systemctl restart mtproxy
    echo -e "${GREEN}Port updated successfully!${NC}"; show_links; read -p "Press Enter to return..."
}

reset_gui_creds() {
    if [[ ! -f "$GUI_CONFIG_FILE" ]]; then echo -e "${RED}GUI is not installed.${NC}"; sleep 1.5; return; fi
    source "$GUI_CONFIG_FILE"
    RAND_USER="admin_$(head -c 2 /dev/urandom | xxd -ps)"
    RAND_PASS=$(head -c 8 /dev/urandom | xxd -ps)
    printf '%s\n' \
        "GUI_PORT=$GUI_PORT" \
        "GUI_USER=\"$RAND_USER\"" \
        "GUI_PASS=\"$RAND_PASS\"" > "$GUI_CONFIG_FILE"
    systemctl restart mtproxy-gui
    echo -e "${GREEN}Web GUI Credentials Reset!${NC}"; show_links; read -p "Press Enter to return..."
}

view_stats() {
    source "$CONFIG_FILE"
    echo -e "\n${CYAN}=== Live Proxy Metrics ===${NC}"
    curl -s "http://127.0.0.1:${STATS_PORT}/stats" | grep -E "total_special|load_average|active_targets" || echo -e "${RED}Failed to fetch stats.${NC}"
    echo ""; read -p "Press Enter to return..."
}

uninstall_all() {
    read -p "Are you sure you want to completely remove MTProxy and Web GUI? (y/n): " CONFIRM
    CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]')
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        systemctl disable --now mtproxy mtproxy-gui &>/dev/null
        rm -f "$SERVICE_FILE" "$GUI_SERVICE_FILE" /etc/cron.daily/mtproxy-update "$CLI_PATH"
        rm -rf "$INSTALL_DIR"
        systemctl daemon-reload
        echo -e "${GREEN}MTProxy Suite successfully removed.${NC}"; exit 0
    fi
}

# --- MAIN MENU ---
if [[ "$1" == "--install" ]]; then
    install_mtproxy
    exit 0
fi

while true; do
    clear
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${CYAN}         MTProxy All-In-One Command Center                    ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    
    if systemctl is-active --quiet mtproxy; then
        echo -e "Proxy Engine Status: ${GREEN}● RUNNING${NC}"
    else
        echo -e "Proxy Engine Status: ${RED}● STOPPED / NOT INSTALLED${NC}"
    fi

    if systemctl is-active --quiet mtproxy-gui; then
        echo -e "Web Dashboard Status: ${GREEN}● RUNNING${NC}"
    else
        echo -e "Web Dashboard Status: ${RED}● STOPPED${NC}"
    fi
    echo "--------------------------------------------------------------"
    echo "1) Install / Reinstall Suite (Core + Web GUI)"
    echo "2) View All Active Links & GUI Credentials"
    echo "3) Interactive Link Controller (Copy Link / Secret / Bot info)"
    echo "4) Change Fake-TLS Spoofing Website"
    echo "5) Set / Change Sponsor Channel (Proxy Tag)"
    echo "6) Regenerate Proxy Secret"
    echo "7) Change Client Listening Port"
    echo "8) Reset Web GUI Password & Username"
    echo "9) View Live C-Engine Stats"
    echo "10) Restart All Services"
    echo "11) View Live System Logs"
    echo "12) Completely Uninstall Suite"
    echo "0) Exit"
    echo "--------------------------------------------------------------"
    read -p "Enter choice [0-12]: " CHOICE
    CHOICE=$(echo "$CHOICE" | tr -d '[:space:]')

    case $CHOICE in
        1) install_mtproxy ;;
        2) show_links; read -p "Press Enter to return..." ;;
        3) manage_links_interactive ;;
        4) change_tls_domain ;;
        5) manage_sponsor ;;
        6) regenerate_secret ;;
        7) change_client_port ;;
        8) reset_gui_creds ;;
        9) view_stats ;;
        10) systemctl restart mtproxy mtproxy-gui && echo -e "${GREEN}All Services Restarted!${NC}"; sleep 1 ;;
        11) journalctl -u mtproxy -u mtproxy-gui -f ;;
        12) uninstall_all ;;
        0) exit 0 ;;
        *) echo -e "${RED}[Error] Invalid option. Returning safely to menu...${NC}" ; sleep 1.5 ;;
    esac
done
