from fastapi import APIRouter

router = APIRouter()

# دریافت تنظیمات
@router.get("/")
def get_settings():
    return {"message": "Settings data"}

# به‌روزرسانی تنظیمات
@router.put("/")
def update_settings():
    return {"message": "Settings updated successfully"}
