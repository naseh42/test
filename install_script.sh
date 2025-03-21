#!/bin/bash

# بررسی دسترسی‌های root
if [ "$EUID" -ne 0 ]; then
    echo "لطفاً این اسکریپت را با دسترسی‌های root اجرا کنید."
    exit 1
fi

echo "شروع نصب و پیکربندی پروژه..."

# نصب ابزارهای ضروری
echo "نصب ابزارهای مورد نیاز..."
apt update && apt install -y python3 python3-pip sqlite3 unzip jq curl wget wireguard-tools uuid-runtime openssl certbot || { echo "خطا در نصب ابزارهای ضروری"; exit 1; }

# نصب virtualenv برای مدیریت محیط مجازی
echo "نصب virtualenv..."
pip3 install virtualenv || { echo "خطا در نصب virtualenv"; exit 1; }

# تنظیم دایرکتوری پروژه
PROJECT_DIR="/opt/backend"
mkdir -p $PROJECT_DIR
echo "انتقال فایل‌های پروژه..."
if ! cp -r ./backend/* $PROJECT_DIR/; then
    echo "خطا در انتقال فایل‌های پروژه"
    exit 1
fi

# تولید UUID یکتا برای کانفیگ Xray و WireGuard
echo "تولید UUID و کلیدهای WireGuard..."
UUID=$(uuidgen)
WG_PRIVATE_KEY=$(wg genkey)
WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey)
WG_CLIENT_PRIVATE_KEY=$(wg genkey)
WG_CLIENT_PUBLIC_KEY=$(echo "$WG_CLIENT_PRIVATE_KEY" | wg pubkey)

# ایجاد فایل requirements.txt
echo "ایجاد فایل requirements.txt..."
cat <<EOL > $PROJECT_DIR/requirements.txt
fastapi
sqlalchemy
pydantic
uvicorn
EOL

# تنظیم PYTHONPATH
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

# تنظیم دسترسی‌ها
chmod -R 755 $PROJECT_DIR || { echo "خطا در تنظیم دسترسی‌ها"; exit 1; }

# پرسش از کاربر درباره دامنه
echo "آیا می‌خواهید دامنه‌ای اضافه کنید و برای آن گواهی TLS دریافت کنید؟ (y/n)"
read -r ADD_DOMAIN

if [[ "$ADD_DOMAIN" == "y" ]]; then
    # دریافت نام دامنه از کاربر
    echo "لطفاً دامنه مورد نظر را وارد کنید:"
    read -r DOMAIN_NAME

    # اجرای Certbot برای دریافت گواهی دامنه
    echo "دریافت گواهی‌های TLS برای دامنه $DOMAIN_NAME..."
    certbot certonly --standalone --agree-tos --email your-email@example.com -d "$DOMAIN_NAME" || { echo "خطا در دریافت گواهی‌های TLS"; exit 1; }

    # تنظیم مسیر فایل‌های گواهی در کانفیگ Xray
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
else
    echo "گواهی Self-Signed برای سرور ایجاد می‌شود..."

    # ایجاد گواهی Self-Signed
    mkdir -p /etc/selfsigned
    openssl req -newkey rsa:2048 -nodes -keyout /etc/selfsigned/selfsigned.key -x509 -days 365 -out /etc/selfsigned/selfsigned.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

    # تنظیم مسیر فایل‌های گواهی Self-Signed در کانفیگ Xray
    CERT_PATH="/etc/selfsigned/selfsigned.crt"
    KEY_PATH="/etc/selfsigned/selfsigned.key"
fi

# ایجاد فایل کانفیگ Xray با مسیر فایل‌های گواهی
echo "ایجاد فایل کانفیگ Xray..."
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
            "id": "$UUID",
            "level": 0,
            "email": "default@example.com"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_PATH",
              "keyFile": "$KEY_PATH"
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

# پیکربندی و راه‌اندازی WireGuard
echo "ایجاد فایل کانفیگ WireGuard..."
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
echo "ایجاد فایل کانفیگ کلاینت WireGuard..."
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

# ریستارت سرویس Xray
echo "راه‌اندازی سرویس Xray..."
systemctl daemon-reload
systemctl enable xray.service
systemctl start xray.service || { echo "خطا در راه‌اندازی Xray"; exit 1; }

# اتمام نصب
echo "نصب و پیکربندی با موفقیت انجام شد!"
echo "فایل‌های کانفیگ در مسیر‌های مربوطه ذخیره شده‌اند."
