#!/bin/bash

# Script برای نصب و راه‌اندازی پروژه

# بررسی دسترسی‌های root
if [ "$EUID" -ne 0 ]
  then echo "لطفاً این اسکریپت را با دسترسی‌های root اجرا کنید."
  exit
fi

echo "شروع نصب پروژه..."

# نصب ابزارهای مورد نیاز
echo "نصب Python و pip..."
apt update && apt install -y python3 python3-pip

echo "نصب SQLite برای مدیریت پایگاه داده..."
apt install -y sqlite3

echo "نصب کتابخانه‌های Python مورد نیاز..."
pip3 install fastapi sqlalchemy pydantic uvicorn

# انتقال فایل‌ها به مسیرهای مناسب
echo "انتقال فایل‌های پروژه..."
mkdir -p /opt/backend
cp -r ./backend/* /opt/backend/

echo "فایل‌ها منتقل شدند!"

# ساخت پایگاه داده و پیکربندی اولیه
echo "ایجاد پایگاه داده..."
sqlite3 /opt/backend/test.db <<EOF
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    uuid TEXT NOT NULL UNIQUE,
    traffic_limit INTEGER,
    usage_duration INTEGER,
    simultaneous_connections INTEGER
);
EOF

echo "پایگاه داده ساخته شد."

echo "اضافه کردن اطلاعات پیش‌فرض به پایگاه داده..."
sqlite3 /opt/backend/test.db <<EOF
INSERT INTO users (username, uuid, traffic_limit, usage_duration, simultaneous_connections)
VALUES ('admin', '123e4567-e89b-12d3-a456-426614174001', 1000, 365, 5);
EOF

echo "اطلاعات پیش‌فرض به پایگاه داده اضافه شد."

# تنظیم دسترسی‌ها
echo "تنظیم دسترسی فایل‌ها..."
chmod -R 755 /opt/backend

# راه‌اندازی برنامه
echo "راه‌اندازی برنامه با uvicorn..."
cd /opt/backend
uvicorn app:app --host 0.0.0.0 --port 8000 --reload

echo "پروژه با موفقیت نصب و اجرا شد!"
