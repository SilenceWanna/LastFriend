-- ============================================================================
-- scripts/relationshipstate.lua
-- 角色关系值的可复用状态单元。
-- ============================================================================

local RelationshipState = {}

local DEFAULT_TRUST = 50
local trust_ = DEFAULT_TRUST

local function Clamp(value)
    return math.max(0, math.min(100, value))
end

function RelationshipState.Reset(value)
    trust_ = Clamp(type(value) == "number" and value or DEFAULT_TRUST)
    return trust_
end

function RelationshipState.Add(delta)
    trust_ = Clamp(trust_ + (tonumber(delta) or 0))
    return trust_
end

function RelationshipState.Get()
    return trust_
end

function RelationshipState.Meets(threshold)
    return trust_ >= (tonumber(threshold) or 0)
end

function RelationshipState.GetTrustLevel()
    if trust_ >= 80 then return "trust" end
    if trust_ >= 50 then return "normal" end
    if trust_ >= 30 then return "cautious" end
    return "hostile"
end

function RelationshipState.GetCharacterState()
    if trust_ >= 80 then return "willing" end
    if trust_ >= 50 then return "observing" end
    if trust_ >= 35 then return "disappointed" end
    return "leaving"
end

return RelationshipState
