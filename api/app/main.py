from fastapi import FastAPI

from app.config import settings

app = FastAPI(title="Fund & Portfolio Intelligence API", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.app_env}
