from sqlalchemy import Column, Integer, String
from backend.database import Base

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    uuid = Column(String, unique=True, index=True)
    traffic_limit = Column(Integer)
    usage_duration = Column(Integer)
    simultaneous_connections = Column(Integer)
