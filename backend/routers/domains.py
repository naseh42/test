from fastapi import APIRouter

router = APIRouter()

# لیست دامنه‌ها
@router.get("/")
def get_domains():
    return {"message": "List of domains"}

# افزودن دامنه جدید
@router.post("/")
def add_domain():
    return {"message": "Domain added successfully"}
