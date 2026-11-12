from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_env: str = "development"
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = ""
    knowledge_db_path: str = "./data/knowledge/assistant_vet_knowledge.sqlite3"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def knowledge_db(self) -> Path:
        return Path(self.knowledge_db_path)

settings = Settings()
