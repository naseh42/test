from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from backend.schemas import UserCreate
from backend.models import User
from backend.database import get_db

router = APIRouter()

# لیست کاربران
@router.get("/")
def get_users(db: Session = Depends(get_db)):
    users = db.query(User).all()
    return users

# اضافه کردن کاربر جدید
@router.post("/")
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    new_user = User(
        username=user.username,
        uuid=user.uuid,
        traffic_limit=user.traffic_limit,
        usage_duration=user.usage_duration,
        simultaneous_connections=user.simultaneous_connections
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

# ویرایش کاربر
@router.put("/{user_id}")
def update_user(user_id: int, user: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")
    db_user.username = user.username
    db_user.traffic_limit = user.traffic_limit
    db_user.usage_duration = user.usage_duration
    db_user.simultaneous_connections = user.simultaneous_connections
    db.commit()
    db.refresh(db_user)
    return db_user
