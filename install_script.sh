#!/bin/bash

# بررسی دسترسی‌های root
if [ "$EUID" -ne 0 ]; then
    echo "لطفاً این اسکریپت را با دسترسی‌های root اجرا کنید."
    exit
fi

echo "شروع نصب پروژه..."

# نصب ابزارهای مورد نیاز
echo "نصب Python و pip..."
apt update && apt install -y python3 python3-pip

echo "نصب SQLite برای مدیریت پایگاه داده..."
apt install -y sqlite3

echo "نصب virtualenv برای مدیریت محیط مجازی..."
pip3 install virtualenv

# انتقال فایل‌ها به مسیر مناسب
echo "انتقال فایل‌های کلون شده..."
PROJECT_DIR="/opt/backend"
mkdir -p $PROJECT_DIR
cp -r ./backend/* $PROJECT_DIR/

echo "تمام فایل‌ها به مسیر $PROJECT_DIR منتقل شدند!"

# ایجاد فایل requirements.txt (اگر قبلاً وجود ندارد)
echo "ایجاد یا اطمینان از وجود فایل requirements.txt..."
cat <<EOL > $PROJECT_DIR/requirements.txt
fastapi
sqlalchemy
pydantic
uvicorn
EOL

echo "فایل requirements.txt ایجاد شد!"

# ایجاد محیط مجازی پایتون
echo "ایجاد محیط مجازی پایتون..."
cd $PROJECT_DIR
virtualenv venv

echo "فعال‌سازی محیط مجازی..."
source venv/bin/activate

# نصب وابستگی‌ها در محیط مجازی
echo "نصب وابستگی‌های پروژه از فایل requirements.txt..."
pip install -r requirements.txt

# ایجاد پایگاه داده و تنظیمات اولیه
echo "ایجاد فایل پایگاه داده..."
sqlite3 $PROJECT_DIR/test.db <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    uuid TEXT NOT NULL UNIQUE,
    traffic_limit INTEGER,
    usage_duration INTEGER,
    simultaneous_connections INTEGER
);
EOF

echo "اضافه کردن اطلاعات پیش‌فرض به پایگاه داده..."
sqlite3 $PROJECT_DIR/test.db <<EOF
INSERT INTO users (username, uuid, traffic_limit, usage_duration, simultaneous_connections)
VALUES ('admin', '123e4567-e89b-12d3-a456-426614174001', 1000, 365, 5)
ON CONFLICT DO NOTHING;
EOF

echo "پایگاه داده با موفقیت پیکربندی شد!"

# ایجاد فایل Systemd برای اجرای دائمی
echo "ایجاد فایل backend.service برای مدیریت اجرای دائمی..."
cat <<EOL > /etc/systemd/system/backend.service
[Unit]
Description=Backend FastAPI Application
After=network.target

[Service]
User=root
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOL

echo "فایل backend.service ایجاد شد!"

# فعال‌سازی سرویس
echo "فعال‌سازی و راه‌اندازی سرویس backend.service..."
systemctl daemon-reload
systemctl enable backend.service
systemctl start backend.service

echo "پروژه با موفقیت نصب و راه‌اندازی شد و به صورت خودکار اجرا می‌شود!"

# غیر فعال‌سازی محیط مجازی پس از پایان نصب
deactivate
