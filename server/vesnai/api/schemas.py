"""Pydantic request/response models for the API."""

from __future__ import annotations

from pydantic import BaseModel, Field


class PairRequest(BaseModel):
    code: str
    device_name: str = "device"


class PairResponse(BaseModel):
    token: str
    device_id: str


class PairCodeResponse(BaseModel):
    code: str
    expires_in: int
    url: str
    qr_svg: str


class BackupRequest(BaseModel):
    passphrase: str | None = None


class DeviceOut(BaseModel):
    device_id: str
    name: str
    created: str


class NoteCreate(BaseModel):
    title: str = ""
    body: str = ""
    type: str = "Note"
    tags: list[str] = Field(default_factory=list)


class NoteUpdate(BaseModel):
    title: str | None = None
    body: str | None = None
    tags: list[str] | None = None
    type: str | None = None
    done: bool | None = None
    device: str = "server"


class NoteOut(BaseModel):
    path: str
    title: str | None
    type: str | None
    tags: list[str]
    origin: str
    body: str
    links: list[str]
    attachments: list[str] = Field(default_factory=list)
    source: str | None = None
    version: int = 1
    updated: str = ""
    done: bool = False
    done_at: str | None = None


class TagSuggestRequest(BaseModel):
    title: str = ""
    body: str = ""


class TagSuggestResponse(BaseModel):
    type: str
    tags: list[str]


class TagFeedbackRequest(BaseModel):
    text: str
    tags: list[str] = Field(default_factory=list)
    action: str = "accepted"  # accepted | rejected | added | removed


class DueNoteOut(BaseModel):
    path: str
    title: str | None


class ResurfacedResponse(BaseModel):
    path: str
    resurface_count: int


class ChangeModel(BaseModel):
    path: str
    deleted: bool = False
    doc: str | None = None


class PushRequest(BaseModel):
    changes: list[ChangeModel] = Field(default_factory=list)
    device: str = "device"


class LocationContextIn(BaseModel):
    lat: float
    lon: float
    label: str | None = None
    accuracy_m: float | None = None
    captured_at: str | None = None


class ChatRequest(BaseModel):
    message: str = ""
    persist: bool = False
    assistant_language: str | None = None
    session_id: str | None = None
    attachment_refs: list[dict] = Field(default_factory=list)
    language: str | None = None  # deprecated alias
    location_context: LocationContextIn | None = None


class ChatResponse(BaseModel):
    status: str = "accepted"
    content: str = ""
    tool_calls: list[dict] = Field(default_factory=list)
    transcript_path: str | None = None
    session_id: str | None = None
    language: str | None = None
    pending_jobs: list[dict] = Field(default_factory=list)
    message_id: str | None = None
    user_message_id: str | None = None
    assistant_message_id: str | None = None
    queue_position: int = 1


class ChatAttachmentOut(BaseModel):
    path: str
    kind: str
    filename: str
    mime: str = ""


class ChatMessageOut(BaseModel):
    role: str
    content: str
    ts: str
    id: str = ""
    attachments: list[ChatAttachmentOut] = Field(default_factory=list)
    metadata: dict = Field(default_factory=dict)


class RetryChatActionRequest(BaseModel):
    action: str = "generate_image"


class RetryChatActionResponse(BaseModel):
    job_id: str
    action: str
    status: str


class ChatSessionOut(BaseModel):
    id: str
    title: str
    created: str
    updated: str
    language: str | None = None


class ChatSessionDetail(ChatSessionOut):
    messages: list[ChatMessageOut] = Field(default_factory=list)


class CreateSessionRequest(BaseModel):
    title: str | None = None


class NotificationOut(BaseModel):
    id: str
    kind: str
    title: str
    source_path: str | None = None
    image_path: str | None = None
    session_id: str | None = None
    attachment_path: str | None = None
    message_id: str | None = None
    note_path: str | None = None
    pending_image: bool = False
    ts: str
    read: bool = False


class SaveChatAttachmentToNoteRequest(BaseModel):
    note_path: str | None = None
    title: str | None = None


class SaveChatAttachmentToNoteResponse(BaseModel):
    note_path: str
    attachment: str


class NotificationAck(BaseModel):
    ids: list[str] = Field(default_factory=list)


class SearchRequest(BaseModel):
    query: str
    languages: list[str] | None = None
    max_seconds: float = 60.0


class EnrichRequest(BaseModel):
    path: str
    kind: str = "idea"  # idea | photo


class SecretSet(BaseModel):
    name: str
    value: str


class SettingsOut(BaseModel):
    offline_only: bool
    default_chat_model: str
    default_embedding_model: str
    search_languages: list[str]
    search_max_seconds: int
    secret_names: list[str]
    voice_configured: bool = False
    voice_url: str | None = None
    voice_provider: str | None = None


class VoiceRegistrationIn(BaseModel):
    provider: str = "sidecar"  # sidecar | openai
    url: str | None = None
    api_key: str
    voices: dict[str, str] | None = None
    model: str | None = None  # OpenAI model id (e.g. tts-1)


class VoiceRegistrationOut(BaseModel):
    configured: bool
    provider: str | None = None
    url: str | None = None
    secret_name: str | None = None
    voices: dict[str, str] = Field(default_factory=dict)
    model: str | None = None
