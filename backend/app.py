from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from backend.routers import users, domains, settings
from backend.database import Base, engine

# ایجاد شیء FastAPI
app = FastAPI()

# ایجاد جداول پایگاه داده (در صورت نیاز)
Base.metadata.create_all(bind=engine)

# اضافه کردن مسیر فایل‌های استاتیک
app.mount("/static", StaticFiles(directory="backend/static"), name="static")

# تنظیم مسیر قالب‌ها
templates_directory = "backend/templates"

# افزودن روترها
app.include_router(users.router, prefix="/users", tags=["Users"])
app.include_router(domains.router, prefix="/domains", tags=["Domains"])
app.include_router(settings.router, prefix="/settings", tags=["Settings"])

@app.get("/")
def root():
    return {"message": "Welcome to the Backend API!"}
