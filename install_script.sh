#!/bin/bash

# بررسی دسترسی‌های root
if [ "$EUID" -ne 0 ]; then
    echo "لطفاً این اسکریپت را با دسترسی‌های root اجرا کنید."
    exit 1
fi

echo "شروع نصب پروژه..."

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

# نصب و پیکربندی Sing-box
echo "نصب Sing-box..."
TOKEN="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" # توکن شما
ASSET_URL=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.assets[] | select(.name == "sing-box-1.11.5-linux-amd64.tar.gz").browser_download_url')

if [ -z "$ASSET_URL" ]; then
    echo "خطا در یافتن لینک دانلود Sing-box"
    exit 1
fi

wget --header="Authorization: token $TOKEN" -O /tmp/sing-box-linux-amd64.tar.gz "$ASSET_URL" || { echo "خطا در دانلود Sing-box"; exit 1; }
tar -xvf /tmp/sing-box-linux-amd64.tar.gz -C /usr/local/bin/ || { echo "خطا در استخراج Sing-box"; exit 1; }
mv /usr/local/bin/sing-box-1.11.5-linux-amd64/sing-box /usr/local/bin/ || { echo "خطا در انتقال Sing-box به مسیر اجرایی"; exit 1; }
chmod +x /usr/local/bin/sing-box || { echo "خطا در تنظیم مجوزهای اجرایی"; exit 1; }

# ایجاد کانفیگ پیش‌فرض برای Sing-box
echo "ایجاد کانفیگ پیش‌فرض Sing-box..."
mkdir -p /usr/local/etc/sing-box || { echo "خطا در ایجاد دایرکتوری کانفیگ Sing-box"; exit 1; }
cat <<EOL > /usr/local/etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vmess",
      "listen": "0.0.0.0",
      "port": 10086,
      "users": [
        {
          "id": "UUID-2"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOL
