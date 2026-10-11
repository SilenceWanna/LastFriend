local P3State = {}

---@class P3KeyState
---@field photo boolean
---@field band boolean
---@field terminal boolean
---@field recordRestore boolean
---@field recordSleep boolean

---@class P3MemoryState
---@field sharedPast boolean
---@field identityBand boolean
---@field sleepExecution boolean

---@class P3InheritedState
---@field route_map boolean
---@field identity_bracelet boolean

---@class P3FlagState
---@field evidenceOpened boolean
---@field endingStarted boolean
---@field completed boolean

---@class P3StateData
---@field phase string
---@field checkpoint string
---@field minorViewed table<string, boolean>
---@field keys P3KeyState
---@field bandLog string
---@field memories P3MemoryState
---@field inherited P3InheritedState
---@field flags P3FlagState

---@return P3StateData
function P3State.CreateInitialState()
    return {
        phase = "OPENING",
        checkpoint = "P3_START",
        minorViewed = {
            R01 = false,
            R02 = false,
            R03 = false,
            R04 = false,
            R05 = false,
            R06 = false,
            R07 = false,
            R08 = false,
        },
        keys = {
            photo = false,
            band = false,
            terminal = false,
            recordRestore = false,
            recordSleep = false,
        },
        bandLog = "",
        memories = {
            sharedPast = false,
            identityBand = false,
            sleepExecution = false,
        },
        inherited = {
            route_map = false,
            identity_bracelet = false,
        },
        flags = {
            evidenceOpened = false,
            endingStarted = false,
            completed = false,
        },
    }
end

---@return P3StateData
function P3State.Reset()
    return P3State.CreateInitialState()
end

return P3State
