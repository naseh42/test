#!/bin/bash

# بررسی دسترسی‌های root
if [ "$EUID" -ne 0 ]; then
    echo "لطفاً این اسکریپت را با دسترسی‌های root اجرا کنید."
    exit 1
fi

echo "شروع نصب و پیکربندی پروژه..."

# نصب ابزارهای مورد نیاز
echo "نصب ابزارهای ضروری..."
apt update && apt install -y python3 python3-pip sqlite3 unzip jq curl wget wireguard-tools || { echo "خطا در نصب ابزارهای ضروری"; exit 1; }

# نصب virtualenv برای مدیریت محیط مجازی
echo "نصب virtualenv..."
pip3 install virtualenv || { echo "خطا در نصب virtualenv"; exit 1; }

# انتقال فایل‌های پروژه
echo "انتقال فایل‌های پروژه..."
PROJECT_DIR="/opt/backend"
mkdir -p $PROJECT_DIR
if ! cp -r ./backend/* $PROJECT_DIR/; then
    echo "خطا در انتقال فایل‌های پروژه"
    exit 1
fi
echo "تمام فایل‌ها به مسیر $PROJECT_DIR منتقل شدند!"

# ایجاد فایل requirements.txt
echo "ایجاد فایل requirements.txt..."
cat <<EOL > $PROJECT_DIR/requirements.txt
fastapi
sqlalchemy
pydantic
uvicorn
EOL

# تنظیم متغیر محیطی PYTHONPATH
echo "تنظیم PYTHONPATH..."
export PYTHONPATH=/opt
if ! grep -q "PYTHONPATH=/opt" ~/.bashrc; then
    echo "export PYTHONPATH=/opt" >> ~/.bashrc
fi

# ایجاد محیط مجازی پایتون
echo "ایجاد محیط مجازی..."
cd $PROJECT_DIR || { echo "خطا: مسیر پروژه یافت نشد"; exit 1; }
virtualenv venv || { echo "خطا در ایجاد محیط مجازی"; exit 1; }
source venv/bin/activate || { echo "خطا در فعال‌سازی محیط مجازی"; exit 1; }

# نصب وابستگی‌ها
echo "نصب وابستگی‌های پروژه..."
pip install --upgrade pip || { echo "خطا در به‌روزرسانی pip"; exit 1; }
pip install -r requirements.txt || { echo "خطا در نصب وابستگی‌ها"; exit 1; }

# تنظیم دسترسی فایل‌ها و پوشه‌ها
echo "تنظیم دسترسی‌ها..."
chmod -R 755 $PROJECT_DIR || { echo "خطا در تنظیم دسترسی‌ها"; exit 1; }

# نصب و پیکربندی Xray
echo "نصب Xray..."
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
if [ -z "$XRAY_VERSION" ]; then
    echo "خطا در دریافت نسخه Xray"
    exit 1
fi
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/Xray-linux-64.zip || { echo "خطا در دانلود Xray"; exit 1; }
unzip -o /tmp/xray.zip -d /usr/local/bin/ || { echo "خطا در استخراج Xray"; exit 1; }
chmod +x /usr/local/bin/xray

# ایجاد فایل سرویس برای Xray
echo "ایجاد فایل سرویس Xray..."
cat <<EOL > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# ایجاد کانفیگ پیش‌فرض برای Xray
echo "ایجاد کانفیگ پیش‌فرض Xray..."
mkdir -p /usr/local/etc/xray || { echo "خطا در ایجاد دایرکتوری کانفیگ Xray"; exit 1; }
cat <<EOL > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID-1",
            "level": 0,
            "email": "test@example.com"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/path/to/cert.crt",
              "keyFile": "/path/to/cert.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOL

# بارگذاری فایل سرویس و راه‌اندازی Xray
echo "راه‌اندازی سرویس Xray..."
systemctl daemon-reload
systemctl enable xray.service
systemctl start xray.service || { echo "خطا در راه‌اندازی Xray"; exit 1; }

# نصب و پیکربندی WireGuard
echo "نصب WireGuard..."
apt install -y wireguard || { echo "خطا در نصب WireGuard"; exit 1; }

# تولید کلیدهای WireGuard
echo "تولید کلیدهای WireGuard..."
WG_PRIVATE_KEY=$(wg genkey)
WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey)
WG_CLIENT_PRIVATE_KEY=$(wg genkey)
WG_CLIENT_PUBLIC_KEY=$(echo "$WG_CLIENT_PRIVATE_KEY" | wg pubkey)

# ایجاد فایل کانفیگ WireGuard برای سرور
echo "ایجاد فایل کانفیگ برای سرور WireGuard..."
cat <<EOL > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $WG_PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $WG_CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32
EOL

chmod 600 /etc/wireguard/wg0.conf

# ایجاد فایل کانفیگ WireGuard برای کلاینت
echo "ایجاد فایل کانفیگ برای کلاینت WireGuard..."
cat <<EOL > ~/wg-client.conf
[Interface]
PrivateKey = $WG_CLIENT_PRIVATE_KEY
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $WG_PUBLIC_KEY
Endpoint = $(curl -s ifconfig.me):51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOL

# راه‌اندازی سرویس WireGuard
echo "راه‌اندازی سرویس WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0 || { echo "خطا در راه‌اندازی WireGuard"; exit 1; }

# غیر فعال‌سازی محیط مجازی
deactivate

echo "پیکربندی با موفقیت انجام شد!"
echo "فایل کانفیگ کلاینت WireGuard در مسیر '~/wg-client.conf' ذخیره شد."
