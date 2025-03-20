from pydantic import BaseModel

class UserCreate(BaseModel):
    username: str
    uuid: str
    traffic_limit: int
    usage_duration: int
    simultaneous_connections: int
