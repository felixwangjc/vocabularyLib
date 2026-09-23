from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]
Identifier = Annotated[str, StringConstraints(pattern=r'^[a-z0-9][a-z0-9-]{0,79}$')]

class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid')

class Line(StrictModel):
    id: Identifier
    speaker: Text
    en: Text
    zh: Text
    isTarget: bool = False

class Scenario(StrictModel):
    id: Identifier
    titleZh: Text
    lines: list[Line] = Field(min_length=1, max_length=12)
    assetId: Identifier | None = None
    altZh: str = Field(default='', max_length=2000)

    @model_validator(mode='after')
    def check_lines(self):
        if len({x.id for x in self.lines}) != len(self.lines):
            raise ValueError('对话行 ID 不可重复')
        return self

class ContentInput(StrictModel):
    baseRevision: str | None = Field(default=None, max_length=80)
    phrase: Text
    meaningZh: Text
    category: Text
    usageNoteZh: Text
    status: Literal['draft', 'published'] = 'draft'
    scenarios: list[Scenario] = Field(min_length=1, max_length=10)

    @model_validator(mode='after')
    def check_scenarios(self):
        if len({x.id for x in self.scenarios}) != len(self.scenarios):
            raise ValueError('情景 ID 不可重复')
        if self.status == 'published':
            for scenario in self.scenarios:
                if not scenario.assetId or not scenario.altZh.strip():
                    raise ValueError('发布前请为每个情景添加图片和图片说明')
                if not any(line.isTarget for line in scenario.lines):
                    raise ValueError('每个发布情景至少标记一句重点表达')
        return self

class LoginInput(StrictModel):
    password: str = Field(min_length=1, max_length=256)

class DeleteInput(StrictModel):
    baseRevision: str = Field(min_length=1, max_length=80)
