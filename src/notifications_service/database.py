from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool
from .config import settings

engine = create_async_engine(settings.database_url, poolclass=NullPool)
session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
